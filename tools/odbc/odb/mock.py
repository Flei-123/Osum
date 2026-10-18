# SPDX-License-Identifier: GPL-2.0-only
"""Mock odbd agent (Python counterpart for tests; speaks the proto.py draft).

  python3 -I -m odb.mock --unix /tmp/odb.sock [--token T]
  python3 -I -m odb.mock --tcp 127.0.0.1:7777
Fault knobs (for tests): noise_every (inject garbage bytes before every N-th
reply frame), corrupt_every (flip a byte in every N-th reply frame), chunk
(write in small pieces to emulate a slow UART).
"""
import os
import socket
import struct
import sys
import threading
import time
import zlib

from . import frame as F
from . import proto
from .transport import SocketTransport


def tiny_png(w=8, h=8):
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + bytes((x * 30) & 255 for x in range(w)) * 3 for _ in range(h))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


class MockAgent:
    def __init__(self, token=None, noise_every=0, corrupt_every=0, chunk=0, files=None):
        self.token = token
        self.noise_every = noise_every
        self.corrupt_every = corrupt_every
        self.chunk = chunk
        self.fs = dict(files or {})
        self.fs.setdefault("/etc/motd", b"welcome to mock OrientOS\n")
        self.inputs = []
        self.log = []
        self.rebooted = False
        self.authed = token is None
        self.procs = {1: "init", 7: "taskbar", 12: "desktop", 40: "odbd"}
        self.sent = 0
        self.stop = False
        self.push_state = {}

    # ---- plumbing -----------------------------------------------------
    def serve(self, transport):
        dec = F.Decoder()
        while not self.stop:
            d = transport.read(0.1)
            if d is None:
                return
            for fr in dec.feed(d) if d else []:
                try:
                    self.handle(transport, fr)
                except (BrokenPipeError, OSError):
                    return

    def serve_bg(self, transport):
        th = threading.Thread(target=self.serve, args=(transport,), daemon=True)
        th.start()
        return th

    def out(self, tr, typ, fid, payload=b"", flags=0):
        raw = F.encode(F.Frame(typ, fid, payload, flags))
        self.sent += 1
        if self.noise_every and self.sent % self.noise_every == 0:
            raw = b"\x00noise ODB\xff\xfe" + raw
        if self.corrupt_every and self.sent % self.corrupt_every == 0:
            b = bytearray(raw)
            b[len(b) // 2] ^= 0x55
            raw = bytes(b)
        if self.chunk:
            for i in range(0, len(raw), self.chunk):
                tr.write(raw[i:i + self.chunk])
        else:
            tr.write(raw)

    def err(self, tr, fid, code, msg):
        self.out(tr, F.ERR, fid, proto.enc_kv({"code": code, "msg": msg}))

    # ---- request handling ---------------------------------------------
    def handle(self, tr, fr):
        if fr.type == F.PING:
            self.out(tr, F.PING, fr.id, fr.payload)
            return
        if fr.type in (F.DATA, F.END):
            st = self.push_state.get(fr.id)
            if st is None:
                return
            if fr.type == F.DATA:
                st["buf"] += fr.payload
            else:
                self.fs[st["path"]] = bytes(st["buf"])
                del self.push_state[fr.id]
                self.out(tr, F.END, fr.id, proto.enc_kv(
                    {"size": len(st["buf"]), "crc32": zlib.crc32(bytes(st["buf"])) & 0xFFFFFFFF}))
            return
        if fr.type != F.REQ:
            return
        op, a = proto.dec_req(fr.payload)
        self.log.append((op, a))
        if op == "hello":
            if self.token is not None and a.get("token") != self.token:
                return self.err(tr, fr.id, 13, "bad token")
            self.authed = True
            return self.out(tr, F.RESP, fr.id, proto.enc_kv(
                {"agent": "mock-odbd", "proto": 1, "os": "OrientOS-mock"}))
        if not self.authed:
            return self.err(tr, fr.id, 13, "not authenticated")
        fn = getattr(self, "op_" + op, None)
        if not fn:
            return self.err(tr, fr.id, 38, "unknown op " + op)
        fn(tr, fr, a)

    def op_info(self, tr, fr, a):
        self.out(tr, F.RESP, fr.id, proto.enc_kv({
            "os": "OrientOS-mock", "uptime_s": 123, "ncpu": 2, "mem_total_kb": 4194304,
            "mem_free_kb": 3000000, "idle_pct": 97, "screen": "1024x768", "tx": "serial"}))

    def op_exec(self, tr, fr, a):
        cmd = a.get("cmd", "")
        w = cmd.split()
        code = 0
        if w[:1] == ["echo"]:
            self.out(tr, F.DATA, fr.id, (" ".join(w[1:]) + "\n").encode())
        elif w[:1] == ["cat"] and len(w) > 1:
            if w[1] in self.fs:
                self.out(tr, F.DATA, fr.id, self.fs[w[1]])
            else:
                self.out(tr, F.DATA, fr.id, b"cat: no such file\n", proto.FLAG_STDERR)
                code = 1
        elif w[:1] == ["big"]:
            n = int(w[1]) if len(w) > 1 else 100000
            blob = (b"0123456789abcdef" * ((n // 16) + 1))[:n]
            for off in range(0, n, 8192):
                self.out(tr, F.DATA, fr.id, blob[off:off + 8192])
        elif w[:1] == ["false"]:
            code = 1
        else:
            self.out(tr, F.DATA, fr.id, b"mock: " + cmd.encode() + b"\n")
        self.out(tr, F.END, fr.id, proto.enc_kv({"code": code}))

    op_shell = op_exec

    def op_push(self, tr, fr, a):
        self.push_state[fr.id] = {"path": a.get("path", ""), "buf": bytearray()}

    def op_pull(self, tr, fr, a):
        p = a.get("path", "")
        if p not in self.fs:
            return self.err(tr, fr.id, 2, "no such file: " + p)
        b = self.fs[p]
        for off in range(0, len(b), 8192):
            self.out(tr, F.DATA, fr.id, b[off:off + 8192])
        self.out(tr, F.END, fr.id, proto.enc_kv({"size": len(b), "crc32": zlib.crc32(b) & 0xFFFFFFFF}))

    def op_shot(self, tr, fr, a):
        png = tiny_png()
        self.out(tr, F.DATA, fr.id, png)
        self.out(tr, F.END, fr.id, proto.enc_kv({"fmt": "png", "w": 8, "h": 8, "size": len(png)}))

    def op_input(self, tr, fr, a):
        self.inputs.append(dict(a))
        self.out(tr, F.RESP, fr.id, proto.enc_kv({"ok": 1}))

    def op_ps(self, tr, fr, a):
        txt = "".join("%5d %s\n" % (p, n) for p, n in sorted(self.procs.items()))
        self.out(tr, F.DATA, fr.id, txt.encode())
        self.out(tr, F.END, fr.id, proto.enc_kv({"count": len(self.procs)}))

    def op_kill(self, tr, fr, a):
        pid = int(a.get("pid", "0"))
        if pid not in self.procs:
            return self.err(tr, fr.id, 3, "no such process")
        del self.procs[pid]
        self.out(tr, F.RESP, fr.id, proto.enc_kv({"ok": 1}))

    def op_logs(self, tr, fr, a):
        self.out(tr, F.DATA, fr.id, b"[ 0.1] boot\n[ 1.2] odbd up\n")
        self.out(tr, F.END, fr.id, proto.enc_kv({"lines": 2}))

    def op_crash(self, tr, fr, a):
        self.out(tr, F.DATA, fr.id, b"no crash recorded\n")
        self.out(tr, F.END, fr.id, proto.enc_kv({"crashes": 0}))

    def op_reboot(self, tr, fr, a):
        self.rebooted = True
        self.out(tr, F.RESP, fr.id, proto.enc_kv({"ok": 1, "mode": a.get("mode", "reboot")}))


def main(argv):
    import argparse
    ap = argparse.ArgumentParser(prog="odb.mock")
    ap.add_argument("--unix")
    ap.add_argument("--tcp")
    ap.add_argument("--token")
    ap.add_argument("--chunk", type=int, default=0)
    ns = ap.parse_args(argv)
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
    agent = MockAgent(token=ns.token, chunk=ns.chunk)
    while True:
        c, _ = s.accept()
        agent.authed = agent.token is None
        agent.serve_bg(SocketTransport(c).start())


if __name__ == "__main__":
    main(sys.argv[1:])
