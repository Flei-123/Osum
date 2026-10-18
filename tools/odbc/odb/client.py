# SPDX-License-Identifier: GPL-2.0-only
"""Request/response session (docs/ODB.md) over any Transport."""
import collections
import hashlib
import hmac
import threading
import time
import zlib

from . import frame as F
from . import proto
from .proto import AgentError
from .transport import open_transport


class Timeout(Exception):
    pass


class Closed(Exception):
    pass


def crc32(b, c=0):
    return zlib.crc32(b, c) & 0xFFFFFFFF


def auth_mac(token, nonce_hex):
    if isinstance(token, str):
        token = token.encode()
    return hmac.new(token, b"ODB1-auth" + bytes.fromhex(nonce_hex), hashlib.sha256).hexdigest()


def read_token_file(path):
    return open(path, "rb").read().decode("utf-8", "replace").strip()


class Session:
    def __init__(self, transport, token=None, client="odbc", retry_s=2.0, retries=5, ack_timeout=2.0):
        self.t = transport
        self.dec = F.Decoder()
        self.pending = []
        self.next_id = 1
        self.token = token
        self.client = client
        self.retry_s = retry_s
        self.retries = retries
        self.ack_timeout = ack_timeout
        self.stray = collections.deque(maxlen=64)   # frames of other request ids (late answers, EBUSY, ...)
        self.wlock = threading.Lock()
        self.hello_info = None
        self.maxchunk = proto.MAX_CHUNK
        self.window = 65536
        self.push_window = 65536
        self.stats = {"tx_frames": 0, "rx_frames": 0, "retries": 0, "rewinds": 0}

    @classmethod
    def open(cls, spec, wait=0.0, token=None, **kw):
        return cls(open_transport(spec, wait), token, **kw)

    def close(self):
        self.t.close()

    # ---- low level ----------------------------------------------------
    def send(self, f):
        self.stats["tx_frames"] += 1
        with self.wlock:
            self.t.write(F.encode(f))

    def poll(self, timeout):
        """Next frame or None after timeout. Raises Closed on EOF."""
        end = time.time() + timeout
        while True:
            if self.pending:
                self.stats["rx_frames"] += 1
                return self.pending.pop(0)
            left = end - time.time()
            if left <= 0:
                return None
            d = self.t.read(min(left, 0.05))
            if d is None:
                raise Closed("transport closed")
            if d:
                self.pending.extend(self.dec.feed(d))

    def new_id(self):
        i = self.next_id
        self.next_id = self.next_id % 0xFFFFFFFF + 1
        return i

    def ping(self, payload=b"odbc", timeout=2.0):
        """Round-trip time in seconds."""
        fid = self.new_id()
        t0 = time.time()
        self.send(F.Frame(F.PING, fid, payload))
        while time.time() - t0 < timeout:
            f = self.poll(0.05)
            if f and f.type == F.PONG and f.id == fid:
                return time.time() - t0
        raise Timeout("no PONG within %.1fs" % timeout)

    # ---- request engine -------------------------------------------------
    def request(self, cmd, items=None, on_frame=None, on_start=None, timeout=15.0, flags=0):
        """Send REQ, handle frames of this id until RESP (returns Tlv) or ERR (raises).
        on_frame(frame) sees every DATA/END/ACK/other frame of the request.
        timeout = max seconds without any frame of this request (after retries)."""
        fid = self.new_id()
        req = F.Frame(F.REQ, fid, proto.enc_req(cmd, items), flags)
        self.send(req)
        if on_start:
            on_start(fid)
        return self._await(fid, req, on_frame, timeout)

    def _await(self, fid, req, on_frame, timeout, idle_hook=None):
        t_act = t_sent = time.time()
        seen = False
        tries = 0
        while True:
            now = time.time()
            if now - t_act > timeout:
                raise Timeout("%s: no answer within %.1fs" % (F.TYPE_NAMES.get(req.type), timeout))
            if not seen and tries < self.retries and now - t_sent >= self.retry_s:
                tries += 1
                self.stats["retries"] += 1
                t_sent = now
                self.send(F.Frame(F.REQ, fid, req.payload, req.flags | F.FLAG_RETRY))
            f = self.poll(0.05)
            if f is None:
                if idle_hook:
                    idle_hook()
                continue
            if f.type in (F.PING, F.PONG):
                continue
            if f.id != fid:
                self.stray.append(f)
                continue
            seen = True
            t_act = time.time()
            if f.type == F.RESP:
                return proto.dec_tlv(f.payload)
            if f.type == F.ERR:
                raise proto.err_from(f.payload)
            if on_frame:
                on_frame(f)
            if idle_hook:
                idle_hook()

    def cancel(self, fid):
        self.send(F.Frame(F.CANCEL, fid))

    def send_stream(self, fid, stream, data, chunk=None):
        chunk = chunk or self.maxchunk
        for off in range(0, len(data), chunk):
            self.send(F.Frame(F.DATA, fid, proto.enc_data(stream, data[off:off + chunk])))

    def end_stream(self, fid, stream, items=None):
        self.send(F.Frame(F.END, fid, proto.enc_end(stream, items)))

    # ---- session setup ---------------------------------------------------
    def hello(self, timeout=3.0):
        r = self.request("hello", [("ver", 1), ("client", self.client), ("clientver", 1)], timeout=timeout)
        self.hello_info = r
        self.maxchunk = min(r.geti("maxchunk", proto.MAX_CHUNK), proto.MAX_CHUNK)
        # push: one frame in flight at most (host -> agent only; pull keeps the full window). A VirtualBox uart2 pipe has no flow control, the agent loses the head of the next
        # frame while it writes the previous one to disk (24 KiB push wedged the agent; 64 KiB at window=8192: 10.6 KiB/s,
        # 0 rewinds). QEMU backpressures, so there the cost is nil (the line, not the RTT, is the limit).
        self.window = r.geti("window", 65536)
        self.push_window = min(self.window, self.maxchunk)
        return r

    def login(self, timeout=3.0):
        """hello + auth (if the agent asks for it). Returns the hello Tlv."""
        h = self.hello(timeout)
        if h.get("auth") == "token":
            if not self.token:
                raise AgentError("EAUTH", "agent needs a token (--token / --token-file / $ODB_TOKEN)")
            self.request("auth", {"mac": auth_mac(self.token, h.get("nonce", ""))}, timeout=max(timeout, 35.0))
        return h

    # ---- commands ---------------------------------------------------------
    def exec(self, cmd=None, argv=None, cwd=None, env=None, timeout_ms=None, stdin=None,
             on_out=None, on_err=None, timeout=None):
        """Run a command. Returns (Tlv resp, stdout bytes, stderr bytes) unless callbacks consume the output."""
        out, err = bytearray(), bytearray()
        items = [("cmd", cmd), ("arg", argv), ("cwd", cwd), ("env", env), ("timeout_ms", timeout_ms),
                 ("stdin", 1 if stdin is not None else None)]

        def on_frame(f):
            if f.type == F.DATA:
                st, b = proto.dec_data(f.payload)
                if st == proto.STDOUT:
                    (on_out or out.extend)(b)
                elif st == proto.STDERR:
                    (on_err or err.extend)(b)

        def start(fid):
            if stdin is not None:
                self.send_stream(fid, proto.STDIN, stdin)
                self.end_stream(fid, proto.STDIN)
        wait = timeout if timeout is not None else (timeout_ms / 1000.0 + 5 if timeout_ms else 30.0)
        r = self.request("exec", items, on_frame=on_frame, on_start=start, timeout=wait)
        return r, bytes(out), bytes(err)

    def collect_stream(self, cmd, items, stream, sink=None, timeout=15.0):
        """For ps/logs/shot/...: gather one DATA stream until RESP."""
        buf = bytearray()

        def on_frame(f):
            if f.type == F.DATA:
                st, b = proto.dec_data(f.payload)
                if st == stream:
                    (sink or buf.extend)(b)
        r = self.request(cmd, items, on_frame=on_frame, timeout=timeout)
        return r, bytes(buf)

    def push(self, data, path, mode="644", overwrite=True, timeout=15.0, progress=None):
        """Go-back-N file push. Returns resp Tlv; verifies sha256/crc32."""
        size = len(data)
        sha = hashlib.sha256(data).hexdigest()
        st = {"sent": 0, "acked": 0, "end": False, "t": time.time()}
        win = self.push_window
        holder = {}

        def pump():
            fid = holder["fid"]
            while st["sent"] < size and st["sent"] - st["acked"] < win:
                n = min(self.maxchunk, size - st["sent"], win - (st["sent"] - st["acked"]))
                if n <= 0:
                    break
                self.send(F.Frame(F.DATA, fid, proto.enc_file(st["sent"], data[st["sent"]:st["sent"] + n])))
                st["sent"] += n
            if st["sent"] >= size and not st["end"]:
                self.end_stream(fid, proto.FILE, {"size": size, "sha256": sha})
                st["end"] = True
            # no ACK progress for 2 s: resend from the last ACK
            if time.time() - st["t"] > self.ack_timeout:
                st["t"] = time.time()
                if st["acked"] < size or st["end"]:
                    if st["sent"] > st["acked"] or st["end"]:
                        self.stats["rewinds"] += 1
                    st["sent"] = st["acked"]
                    st["end"] = False

        def on_frame(f):
            if f.type == F.ACK:
                s, nxt = proto.dec_ack(f.payload)
                if s != proto.FILE:
                    return
                st["t"] = time.time()
                if nxt < st["sent"] and nxt <= st["acked"]:     # duplicate ACK = the receiver saw a gap
                    self.stats["rewinds"] += 1
                    st["sent"] = nxt
                    st["end"] = False
                st["acked"] = max(st["acked"], nxt) if nxt >= st["acked"] else nxt
                if progress:
                    progress(nxt, size)

        def start(fid):
            holder["fid"] = fid
            st["t"] = time.time()

        fid_items = [("path", path), ("size", size), ("mode", mode), ("sha256", sha), ("overwrite", 1 if overwrite else None)]
        fid = self.new_id()
        holder["fid"] = fid
        req = F.Frame(F.REQ, fid, proto.enc_req("push", fid_items))
        self.send(req)
        pump()
        r = self._await(fid, req, on_frame, timeout, idle_hook=pump)
        if r.get("sha256") and r.get("sha256") != sha:
            raise AgentError("ECRC", "agent sha256 %s != local %s" % (r.get("sha256"), sha))
        if r.geti("crc32") is not None and r.geti("crc32") != crc32(data):
            raise AgentError("ECRC", "agent crc32 mismatch")
        return r

    def pull(self, path, offset=0, timeout=15.0, sink=None, progress=None):
        """Go-back-N file pull. Returns (resp Tlv, bytes); verifies sha256/crc32 of the whole file."""
        return self.file_download("pull", [("path", path), ("offset", offset or None)], offset, timeout, sink, progress)

    def file_download(self, cmd, items, offset=0, timeout=15.0, sink=None, progress=None):
        """Shared by pull and crashdump get: file stream 3 agent->host with ACKs."""
        buf = bytearray()
        st = {"next": offset, "acked": offset, "t": time.time(), "tack": 0.0}
        holder = {}
        win = self.window

        def ack(n=None):
            self.send(F.Frame(F.ACK, holder["fid"], proto.enc_ack(proto.FILE, st["next"])))
            st["acked"] = st["next"]
            st["t"] = st["tack"] = time.time()

        def on_frame(f):
            if f.type == F.DATA:
                try:
                    off, b = proto.dec_file(f.payload)
                except proto.ProtoError:
                    return
                st["t"] = time.time()
                if off > st["next"]:
                    ack()                      # gap: tell the agent where to continue
                    self.stats["rewinds"] += 1
                    return
                short = len(b) < self.maxchunk # a short frame ends a burst (last chunk of a file): nothing else follows
                dup = off < st["next"] or (off == st["next"] and not b)   # the agent resent: it waits for our ACK
                b = b[st["next"] - off:]       # drop a duplicated prefix
                if b:
                    (sink or buf.extend)(b)
                    st["next"] += len(b)
                    if progress:
                        progress(st["next"])
                # ACK at once on a short frame, and on a resend (at most one per 0.5 s). Waiting for window/2 or 2 s of
                # silence deadlocked small pulls on a slow line: the agent (which sends END only after the last ACK)
                # resent every ~1 s, each resend reset our silence timer, so no ACK ever went out (VirtualBox, 100 byte
                # and exactly 8 KiB files). The rate limit avoids an ACK storm after loss.
                if short or (dup and time.time() - st["tack"] > 0.5) or st["next"] - st["acked"] >= win // 2:
                    ack()
            elif f.type == F.END:
                s, _ = proto.dec_end(f.payload)
                if s == proto.FILE:
                    ack()

        def idle():
            if time.time() - st["t"] > self.ack_timeout:     # silence: prompt a resend from where we are
                ack()
                self.stats["rewinds"] += 1

        fid = self.new_id()
        holder["fid"] = fid
        req = F.Frame(F.REQ, fid, proto.enc_req(cmd, items))
        self.send(req)
        r = self._await(fid, req, on_frame, timeout, idle_hook=idle)
        total = r.geti("size")
        if total is not None and total != st["next"]:
            raise AgentError("ECRC", "pulled %d bytes, agent says %d" % (st["next"], total))
        if offset == 0 and sink is None:
            if r.get("sha256") and hashlib.sha256(bytes(buf)).hexdigest() != r.get("sha256"):
                raise AgentError("ECRC", "sha256 mismatch after pull")
            if r.geti("crc32") is not None and crc32(bytes(buf)) != r.geti("crc32"):
                raise AgentError("ECRC", "crc32 mismatch after pull")
        return r, bytes(buf)
