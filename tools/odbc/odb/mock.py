# SPDX-License-Identifier: GPL-2.0-only
"""Mock odbd agent following docs/ODB.md (Python counterpart for tests / host-only runs).

  python3 tools/odbc/odb/mock.py --unix /tmp/odb.sock --token-file tok [--chunk N]

Fault knobs (tests): noise_every (garbage before every N-th frame), corrupt_every
(flip a byte), drop_every (do not send every N-th frame at all), chunk (tiny
writes like a slow UART). One request at a time (EBUSY), RETRY cache, CANCEL, ACK.
"""
import hashlib
import hmac
import os
import queue
import random
import socket
import struct
import sys
import threading
import time
import zlib

if __package__ in (None, ""):
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    __package__ = "odb"

from . import frame as F  # noqa: E402
from . import proto  # noqa: E402
from .transport import SocketTransport  # noqa: E402

FEATURES = "info,exec,shell,push,pull,shot,input,ps,kill,logs,crashdump,power"


def tiny_png(w=8, h=8):
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + bytes((x * 30) & 255 for x in range(w * 3)) for _ in range(h))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


class Job:
    def __init__(self, fid, cmd, args):
        self.fid, self.cmd, self.args = fid, cmd, args
        self.q = queue.Queue()
        self.cancel = threading.Event()


class MockAgent:
    def __init__(self, token="0123456789abcdef-mock", noise_every=0, corrupt_every=0, drop_every=0, chunk=0,
                 files=None, window=65536, maxchunk=32768, allow=None, drop_prob=0.0, resend_s=2.0, end_after_ack=False):
        self.token = token
        self.noise_every, self.corrupt_every, self.drop_every, self.chunk = noise_every, corrupt_every, drop_every, chunk
        self.window, self.maxchunk = window, maxchunk
        self.drop_prob, self.resend_s = drop_prob, resend_s
        self.end_after_ack = end_after_ack   # like the real odbd: END only after the last byte is ACKed (pull)
        self.rnd = random.Random(4711)
        self.allow = set(allow.split(",")) if allow else None
        self.fs = dict(files or {})
        self.fs.setdefault("/etc/motd", b"welcome to mock OrientOS\n")
        self.inputs, self.log, self.rebooted, self.killed = [], [], None, []
        self.procs = {1: "init", 7: "taskbar", 12: "desktop", 40: "odbd"}
        self.crashes = {"c1": b"panic: mock crash dump\n"}
        self.sent = 0
        self.stop = False
        self.bad_auth = 0
        self.reset_session()
        self.lock = threading.Lock()

    def reset_session(self):
        self.authed = False
        self.nonce = None
        self.job = None
        self.cache = {}

    # ---- plumbing -----------------------------------------------------
    def serve(self, tr):
        dec = F.Decoder()
        self.reset_session()
        while not self.stop:
            d = tr.read(0.1)
            if d is None:
                return
            for fr in dec.feed(d) if d else []:
                try:
                    self.handle(tr, fr)
                except OSError:
                    return

    def serve_bg(self, tr):
        th = threading.Thread(target=self.serve, args=(tr,), daemon=True)
        th.start()
        return th

    def out(self, tr, typ, fid, payload=b"", flags=0):
        raw = F.encode(F.Frame(typ, fid, payload, flags))
        with self.lock:
            self.sent += 1
            n = self.sent
            if (self.drop_every and n % self.drop_every == 0) or (self.drop_prob and self.rnd.random() < self.drop_prob):
                return
            if self.noise_every and n % self.noise_every == 0:
                raw = b"\x00noise OD\xff" + raw
            if self.corrupt_every and n % self.corrupt_every == 0:
                b = bytearray(raw)
                b[len(b) // 2] ^= 0x55
                raw = bytes(b)
            if self.chunk:
                for i in range(0, len(raw), self.chunk):
                    tr.write(raw[i:i + self.chunk])
            else:
                tr.write(raw)

    def final(self, tr, fid, typ, payload):
        self.cache[fid] = (typ, payload)
        self.job = None
        self.out(tr, typ, fid, payload)

    def resp(self, tr, fid, items=None):
        self.final(tr, fid, F.RESP, proto.enc_tlv(items or {}))

    def err(self, tr, fid, code, msg="", errno=None):
        self.final(tr, fid, F.ERR, proto.enc_tlv([("code", code), ("msg", msg), ("errno", errno)]))

    # ---- dispatch -------------------------------------------------------
    def handle(self, tr, fr):
        if fr.type == F.PING:
            return self.out(tr, F.PONG, fr.id, fr.payload)
        if fr.type in (F.DATA, F.END, F.ACK, F.CANCEL):
            j = self.job
            if j is not None and j.fid == fr.id:
                if fr.type == F.CANCEL:
                    j.cancel.set()
                j.q.put(fr)
            return
        if fr.type != F.REQ:
            return self.err(tr, fr.id, "EUNSUP", "unknown frame type %d" % fr.type)
        if (fr.flags & F.FLAG_RETRY) and fr.id in self.cache:
            t, p = self.cache[fr.id]
            return self.out(tr, t, fr.id, p)
        if self.job is not None and self.job.fid == fr.id:
            return                                  # retry of a running request: ignore
        try:
            cmd, a = proto.dec_req(fr.payload)
        except proto.ProtoError as e:
            return self.err(tr, fr.id, "EPROTO", str(e))
        self.log.append((cmd, a))
        if self.job is not None:
            return self.err(tr, fr.id, "EBUSY", "busy")
        if cmd == "hello":
            if a.geti("ver", 1) != 1:
                return self.err(tr, fr.id, "EVER", "version")
            self.nonce = os.urandom(16)
            self.authed = False
            return self.resp(tr, fr.id, [
                ("ver", 1), ("agent", "odbd"), ("agentver", 1), ("os", "OrientOS"), ("kernel", "mock-1"),
                ("features", FEATURES), ("maxchunk", self.maxchunk), ("window", self.window),
                ("maxpayload", 65536), ("auth", "token"), ("nonce", self.nonce.hex())])
        if cmd == "auth":
            if not self.token or self.nonce is None:
                return self.err(tr, fr.id, "EAUTH", "auth refused")
            want = hmac.new(self.token.encode(), b"ODB1-auth" + self.nonce, hashlib.sha256).hexdigest()
            if hmac.compare_digest(want, a.get("mac", "")):
                self.authed = True
                return self.resp(tr, fr.id, {"ok": 1})
            self.bad_auth += 1
            return self.err(tr, fr.id, "EAUTH", "bad mac")
        if cmd == "ping":
            return self.resp(tr, fr.id, {"ok": 1})
        if not self.authed:
            return self.err(tr, fr.id, "EAUTH", "not authenticated")
        feat = {"push": "push", "pull": "pull", "reboot": "power", "shutdown": "power"}.get(cmd, cmd)
        fn = getattr(self, "cmd_" + cmd, None)
        if not fn:
            return self.err(tr, fr.id, "EUNSUP", "unknown command " + cmd)
        if self.allow is not None and feat not in self.allow:
            return self.err(tr, fr.id, "EACCES", "disabled by allow=")
        j = Job(fr.id, cmd, a)
        self.job = j
        threading.Thread(target=self._run, args=(fn, tr, j), daemon=True).start()

    def _run(self, fn, tr, j):
        try:
            fn(tr, j)
        except OSError:
            pass
        except Exception as e:                       # pragma: no cover
            if self.job is j:
                self.err(tr, j.fid, "EINTERNAL", repr(e))

    # ---- commands (run in a job thread) ------------------------------------
    def cmd_info(self, tr, j):
        self.resp(tr, j.fid, [("os", "OrientOS"), ("kernel", "mock-1"), ("uptime_ms", 123456), ("cpus", 2),
                              ("mem_total_kb", 4194304), ("mem_free_kb", 3000000), ("idle_pct", 97),
                              ("idle_core", "0:98"), ("idle_core", "1:96"), ("procs", len(self.procs)),
                              ("screen", "1024x768"), ("time_unix", int(time.time()))])

    def _sh(self, tr, j, line, stdin=b""):
        w = line.split()
        code = 0
        def so(b, s=proto.STDOUT):
            for off in range(0, max(len(b), 1), self.maxchunk):
                self.out(tr, F.DATA, j.fid, proto.enc_data(s, b[off:off + self.maxchunk]))
        if w[:1] == ["echo"]:
            so((" ".join(w[1:]) + "\n").encode())
        elif w[:1] == ["cat"] and len(w) == 1:
            so(stdin)
        elif w[:1] == ["cat"]:
            if w[1] in self.fs:
                so(self.fs[w[1]])
            else:
                so(b"cat: no such file\n", proto.STDERR)
                code = 1
        elif w[:1] == ["big"]:
            n = int(w[1])
            blob = (b"0123456789abcdef" * (n // 16 + 1))[:n]
            for off in range(0, n, 8192):
                so(blob[off:off + 8192])
        elif w[:1] == ["sleep"]:
            end = time.time() + float(w[1])
            while time.time() < end:
                if j.cancel.wait(0.02):
                    return None
        elif w[:1] == ["false"]:
            code = 1
        elif w[:1] == ["true"]:
            pass
        else:
            so(("mock: " + line + "\n").encode())
        return code

    def cmd_exec(self, tr, j):
        a = j.args
        cmd = a.get("cmd") or " ".join(a.getall("arg"))
        stdin = bytearray()
        if a.get("stdin") == "1":
            while True:
                f = j.q.get()
                if f.type == F.DATA:
                    stdin += proto.dec_data(f.payload)[1]
                elif f.type == F.END:
                    break
                elif f.type == F.CANCEL:
                    return self.err(tr, j.fid, "ECANCEL", "cancelled")
        t0 = time.time()
        code = self._sh(tr, j, cmd, bytes(stdin))
        if code is None:
            return self.err(tr, j.fid, "ECANCEL", "cancelled")
        self.out(tr, F.END, j.fid, proto.enc_end(proto.STDOUT))
        self.out(tr, F.END, j.fid, proto.enc_end(proto.STDERR))
        self.resp(tr, j.fid, [("exit", code), ("signal", 0), ("time_ms", int((time.time() - t0) * 1000))])

    def cmd_shell(self, tr, j):
        buf = b""
        self.out(tr, F.DATA, j.fid, proto.enc_data(proto.STDOUT, b"mock$ "))
        while True:
            f = j.q.get()
            if f.type == F.CANCEL:
                return self.err(tr, j.fid, "ECANCEL", "cancelled")
            if f.type == F.DATA:
                buf += proto.dec_data(f.payload)[1]
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    if line.strip() == b"exit":
                        return self.resp(tr, j.fid, [("exit", 0)])
                    self._sh(tr, j, line.decode(errors="replace"))
                    self.out(tr, F.DATA, j.fid, proto.enc_data(proto.STDOUT, b"mock$ "))

    def cmd_push(self, tr, j):
        a = j.args
        path, size = a.get("path"), a.geti("size", -1)
        if not path or a.get("overwrite") != "1" and path in self.fs:
            return self.err(tr, j.fid, "EARG" if not path else "EACCES", "path")
        buf = bytearray()
        got_end = False
        last_ack = 0
        while not got_end:
            try:
                f = j.q.get(timeout=5)
            except queue.Empty:
                return self.err(tr, j.fid, "ETIMEOUT", "no data")
            if f.type == F.CANCEL:
                return self.err(tr, j.fid, "ECANCEL", "cancelled")
            if f.type == F.DATA:
                try:
                    off, b = proto.dec_file(f.payload)
                except proto.ProtoError:
                    continue
                if off != len(buf):                  # gap or duplicate: ask for the right offset
                    if off < len(buf) and off + len(b) > len(buf):
                        buf += b[len(buf) - off:]
                    self.out(tr, F.ACK, j.fid, proto.enc_ack(proto.FILE, len(buf)))
                    last_ack = len(buf)
                    continue
                buf += b
                if len(buf) - last_ack >= self.window // 2:
                    last_ack = len(buf)
                    self.out(tr, F.ACK, j.fid, proto.enc_ack(proto.FILE, len(buf)))
            elif f.type == F.END:
                if len(buf) < size:                  # END overtook lost data
                    self.out(tr, F.ACK, j.fid, proto.enc_ack(proto.FILE, len(buf)))
                    continue
                got_end = True
        self.out(tr, F.ACK, j.fid, proto.enc_ack(proto.FILE, len(buf)))
        sha = hashlib.sha256(bytes(buf)).hexdigest()
        if a.get("sha256") and a.get("sha256") != sha:
            return self.err(tr, j.fid, "ECRC", "sha256 mismatch")
        self.fs[path] = bytes(buf)
        self.resp(tr, j.fid, [("size", len(buf)), ("sha256", sha), ("crc32", zlib.crc32(bytes(buf)) & 0xFFFFFFFF)])

    def _send_file(self, tr, j, data, offset):
        """Go-back-N sender for pull/crashdump."""
        sent = acked = offset
        end_sent = False
        last = time.time()
        while True:
            while sent < len(data) and sent - acked < self.window:
                n = min(self.maxchunk, len(data) - sent)
                self.out(tr, F.DATA, j.fid, proto.enc_file(sent, data[sent:sent + n]))
                sent += n
            if sent >= len(data) and not end_sent and (not self.end_after_ack or acked >= len(data)):
                self.out(tr, F.END, j.fid, proto.enc_end(proto.FILE, {"size": len(data)}))
                end_sent = True
            try:
                f = j.q.get(timeout=0.05)
            except queue.Empty:
                f = None
            if f is not None:
                if f.type == F.CANCEL:
                    return False
                if f.type == F.ACK:
                    _s, nxt = proto.dec_ack(f.payload)
                    last = time.time()
                    if nxt < sent and nxt <= acked:      # duplicate ACK = gap on the receiver
                        sent, end_sent = nxt, False
                    acked = nxt
                    if acked >= len(data) and (end_sent or self.end_after_ack):
                        if self.end_after_ack and not end_sent:
                            self.out(tr, F.END, j.fid, proto.enc_end(proto.FILE, {"size": len(data)}))
                        return True
            elif time.time() - last > self.resend_s:
                last = time.time()
                sent, end_sent = acked, False
            if j.cancel.is_set():
                return False

    def cmd_pull(self, tr, j):
        p = j.args.get("path", "")
        if p not in self.fs:
            return self.err(tr, j.fid, "ENOENT", "no such file: " + p, 2)
        data = self.fs[p]
        if not self._send_file(tr, j, data, j.args.geti("offset", 0)):
            return self.err(tr, j.fid, "ECANCEL", "cancelled")
        self.resp(tr, j.fid, [("size", len(data)), ("sha256", hashlib.sha256(data).hexdigest()),
                              ("crc32", zlib.crc32(data) & 0xFFFFFFFF), ("mtime", 1760000000)])

    def cmd_shot(self, tr, j):
        fmt = j.args.get("format", "png")
        w = h = 8
        if fmt == "png":
            b = tiny_png(w, h)
        elif fmt == "ppm":
            b = b"P6\n%d %d\n255\n" % (w, h) + bytes(range(256))[:w * h * 3].ljust(w * h * 3, b"\0")
        else:
            b = bytes(w * h * 4)
        for off in range(0, len(b), self.maxchunk):
            self.out(tr, F.DATA, j.fid, proto.enc_data(proto.SHOT, b[off:off + self.maxchunk]))
        self.out(tr, F.END, j.fid, proto.enc_end(proto.SHOT))
        self.resp(tr, j.fid, [("w", w), ("h", h), ("format", fmt), ("bytes", len(b))])

    def cmd_input(self, tr, j):
        self.inputs.append(j.args.as_dict())
        self.resp(tr, j.fid, [("ok", 1), ("n", 1)])

    def cmd_ps(self, tr, j):
        txt = "pid\tppid\tuid\tstate\tcpu_pct\trss_kb\tname\tcmdline\n" + "".join(
            "%d\t0\t0\tS\t0\t100\t%s\t%s\n" % (p, n, n) for p, n in sorted(self.procs.items()))
        self.out(tr, F.DATA, j.fid, proto.enc_data(proto.STDOUT, txt.encode()))
        self.out(tr, F.END, j.fid, proto.enc_end(proto.STDOUT))
        self.resp(tr, j.fid, {"count": len(self.procs)})

    def cmd_kill(self, tr, j):
        pid = j.args.geti("pid", -1)
        if pid not in self.procs:
            return self.err(tr, j.fid, "ENOENT", "no such process")
        self.killed.append((pid, j.args.get("sig", "TERM")))
        del self.procs[pid]
        self.resp(tr, j.fid, {"ok": 1})

    def cmd_logs(self, tr, j):
        lines = ["[0.1] boot", "[1.2] odbd up", "[2.0] desktop started"]
        n = j.args.geti("lines", 200)
        txt = "".join(l + "\n" for l in lines[-n:])
        self.out(tr, F.DATA, j.fid, proto.enc_data(proto.LOG, txt.encode()))
        if j.args.get("follow") == "1":
            i = 0
            while not j.cancel.wait(0.2):
                i += 1
                self.out(tr, F.DATA, j.fid, proto.enc_data(proto.LOG, ("[tick %d]\n" % i).encode()))
            return self.err(tr, j.fid, "ECANCEL", "cancelled")
        self.out(tr, F.END, j.fid, proto.enc_end(proto.LOG))
        self.resp(tr, j.fid, [("lines", min(n, len(lines))), ("bytes", len(txt))])

    def cmd_crashdump(self, tr, j):
        op = j.args.get("op", "list")
        if op == "list":
            txt = "".join("%s %d 1760000000 %s\n" % (k, len(v), v.split(b"\n")[0].decode()) for k, v in self.crashes.items())
            self.out(tr, F.DATA, j.fid, proto.enc_data(proto.STDOUT, txt.encode()))
            return self.resp(tr, j.fid, {"count": len(self.crashes)})
        cid = j.args.get("id")
        if cid not in self.crashes:
            return self.err(tr, j.fid, "ENOENT", "no such dump")
        if op == "clear":
            del self.crashes[cid]
            return self.resp(tr, j.fid, {"count": len(self.crashes)})
        data = self.crashes[cid]
        self._send_file(tr, j, data, 0)
        self.resp(tr, j.fid, {"size": len(data), "sha256": hashlib.sha256(data).hexdigest()})

    def cmd_reboot(self, tr, j):
        self.rebooted = "reboot:" + (j.args.get("mode") or "normal")
        self.resp(tr, j.fid, {"ok": 1})

    def cmd_shutdown(self, tr, j):
        self.rebooted = "shutdown:" + (j.args.get("mode") or "normal")
        self.resp(tr, j.fid, {"ok": 1})


def main(argv):
    import argparse
    ap = argparse.ArgumentParser(prog="odb.mock")
    ap.add_argument("--unix")
    ap.add_argument("--tcp")
    ap.add_argument("--token-file")
    ap.add_argument("--token", default="0123456789abcdef-mock")
    ap.add_argument("--chunk", type=int, default=0)
    ns = ap.parse_args(argv)
    tok = open(ns.token_file).read().strip() if ns.token_file else ns.token
    if ns.unix:
        if os.path.exists(ns.unix):
            os.unlink(ns.unix)
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.bind(ns.unix)
        what = "unix:" + ns.unix
    elif ns.tcp:
        h, _, p = ns.tcp.rpartition(":")
        s = socket.socket()
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((h or "127.0.0.1", int(p)))
        what = "tcp:" + ns.tcp
    else:
        ap.error("need --unix or --tcp")
    s.listen(4)
    print("listening " + what, flush=True)
    agent = MockAgent(token=tok, chunk=ns.chunk)
    while True:
        c, _ = s.accept()
        agent.serve_bg(SocketTransport(c).start())


if __name__ == "__main__":
    main(sys.argv[1:])
