# SPDX-License-Identifier: GPL-2.0-only
"""Request/response session over any Transport."""
import time
import zlib

from . import frame as F
from . import proto
from .transport import open_transport


class Timeout(Exception):
    pass


class Closed(Exception):
    pass


class Session:
    def __init__(self, transport, token=None):
        self.t = transport
        self.dec = F.Decoder()
        self.pending = []
        self.next_id = 1
        self.token = token
        self.stats = {"tx_frames": 0, "rx_frames": 0}

    @classmethod
    def open(cls, spec, wait=0.0, token=None):
        return cls(open_transport(spec, wait), token)

    def close(self):
        self.t.close()

    def send(self, f):
        self.stats["tx_frames"] += 1
        self.t.write(F.encode(f))

    def _recv(self, deadline):
        """Next frame or Timeout. Raises Closed on EOF."""
        while True:
            if self.pending:
                self.stats["rx_frames"] += 1
                return self.pending.pop(0)
            left = deadline - time.time()
            if left <= 0:
                raise Timeout("no frame within timeout")
            d = self.t.read(min(left, 0.2))
            if d is None:
                raise Closed("transport closed")
            if d:
                self.pending.extend(self.dec.feed(d))

    def new_id(self):
        i = self.next_id
        self.next_id = (self.next_id % 0xFFFFFFFF) + 1
        return i

    def ping(self, payload=b"odb", timeout=2.0):
        """Round-trip time in seconds."""
        fid = self.new_id()
        t0 = time.time()
        self.send(F.Frame(F.PING, fid, payload))
        end = t0 + timeout
        while True:
            f = self._recv(end)
            if f.type == F.PING and f.id == fid:
                return time.time() - t0

    def call(self, op, args=None, data=None, on_data=None, timeout=10.0, chunk=4096,
             idle_timeout=None):
        """Send REQ (+ optional DATA stream), collect the answer.
        Returns (end_dict, data_bytes_or_None). on_data(bytes, flags) streams DATA.
        timeout: inactivity timeout (reset on every frame)."""
        fid = self.new_id()
        self.send(F.Frame(F.REQ, fid, proto.enc_req(op, args)))
        if data is not None:
            for off in range(0, len(data), chunk):
                self.send(F.Frame(F.DATA, fid, data[off:off + chunk]))
            self.send(F.Frame(F.END, fid, b""))
        collected = [] if on_data is None else None
        while True:
            f = self._recv(time.time() + timeout)
            if f.id != fid:
                continue            # stale frame of an older request
            if f.type == F.DATA:
                if on_data:
                    on_data(f.payload, f.flags)
                else:
                    collected.append(f.payload)
            elif f.type in (F.END, F.RESP):
                body = b"".join(collected) if collected is not None else None
                return proto.dec_kv(f.payload), body
            elif f.type == F.ERR:
                raise proto.dec_err(f.payload)

    def hello(self, timeout=3.0):
        a = {"token": self.token} if self.token else {}
        r, _ = self.call("hello", a, timeout=timeout)
        return r


def crc32(b):
    return zlib.crc32(b) & 0xFFFFFFFF
