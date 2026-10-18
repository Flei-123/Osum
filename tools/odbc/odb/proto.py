# SPDX-License-Identifier: GPL-2.0-only
"""Payload layer of docs/ODB.md: TLV blocks, command requests, stream payloads, ACKs.

REQ payload  = cmdlen u8 | cmd ASCII | tlv*
RESP/ERR     = tlv*
END          = stream u8 | tlv*
DATA         = stream u8 | bytes   (file stream 3: offset u64 | bytes)
ACK          = stream u8 | next u64
tlv          = klen u8 | key | vlen u16 | value        (repeated key = list)
"""
import struct

STDIN, STDOUT, STDERR, FILE, SHOT, LOG = 0, 1, 2, 3, 4, 5
MAX_CHUNK = 32768


class ProtoError(ValueError):
    pass


class AgentError(Exception):
    def __init__(self, code, msg="", errno=None):
        super().__init__("agent error %s: %s" % (code, msg))
        self.code = code
        self.msg = msg
        self.errno = errno


class Tlv:
    """Ordered (key, bytes) pairs with dict-like helpers."""

    def __init__(self, pairs=()):
        self.pairs = list(pairs)

    def get(self, key, default=None):
        for k, v in self.pairs:
            if k == key:
                return v.decode("utf-8", "replace")
        return default

    def getb(self, key, default=None):
        for k, v in self.pairs:
            if k == key:
                return v
        return default

    def geti(self, key, default=None):
        v = self.get(key)
        if v is None:
            return default
        try:
            return int(v, 0)
        except ValueError:
            return default

    def getall(self, key):
        return [v.decode("utf-8", "replace") for k, v in self.pairs if k == key]

    def __contains__(self, key):
        return any(k == key for k, _ in self.pairs)

    def as_dict(self):
        d = {}
        for k, v in self.pairs:
            d.setdefault(k, v.decode("utf-8", "replace"))
        return d

    def __repr__(self):
        return "Tlv(%s)" % ", ".join("%s=%r" % (k, v.decode("utf-8", "replace")) for k, v in self.pairs)


def _val(v):
    if isinstance(v, bytes):
        return v
    if isinstance(v, bool):
        return b"1" if v else b"0"
    return str(v).encode()


def enc_tlv(items):
    """items: dict or list of (k, v); a list/tuple value = repeated key; None skipped."""
    if hasattr(items, "items"):
        items = items.items()
    out = bytearray()
    for k, v in items:
        if v is None:
            continue
        for one in (v if isinstance(v, (list, tuple)) else [v]):
            kb, vb = k.encode(), _val(one)
            if len(kb) > 255 or len(vb) > 65535:
                raise ProtoError("tlv too long: %s" % k)
            out += bytes([len(kb)]) + kb + struct.pack("<H", len(vb)) + vb
    return bytes(out)


def dec_tlv(b):
    pairs = []
    i, n = 0, len(b)
    while i < n:
        kl = b[i]
        i += 1
        if i + kl + 2 > n:
            raise ProtoError("truncated tlv key")
        k = bytes(b[i:i + kl]).decode("ascii", "replace")
        i += kl
        (vl,) = struct.unpack_from("<H", b, i)
        i += 2
        if i + vl > n:
            raise ProtoError("truncated tlv value")
        pairs.append((k, bytes(b[i:i + vl])))
        i += vl
    return Tlv(pairs)


def enc_req(cmd, items=None):
    c = cmd.encode()
    return bytes([len(c)]) + c + enc_tlv(items or {})


def dec_req(b):
    if not b or 1 + b[0] > len(b):
        raise ProtoError("bad request")
    return bytes(b[1:1 + b[0]]).decode("ascii", "replace"), dec_tlv(b[1 + b[0]:])


def enc_data(stream, data):
    return bytes([stream]) + bytes(data)


def dec_data(p):
    if not p:
        raise ProtoError("empty data")
    return p[0], bytes(p[1:])


def enc_file(offset, data):
    return bytes([FILE]) + struct.pack("<Q", offset) + bytes(data)


def dec_file(p):
    if len(p) < 9 or p[0] != FILE:
        raise ProtoError("bad file data")
    return struct.unpack_from("<Q", p, 1)[0], bytes(p[9:])


def enc_end(stream, items=None):
    return bytes([stream]) + enc_tlv(items or {})


def dec_end(p):
    if not p:
        raise ProtoError("empty end")
    return p[0], dec_tlv(p[1:])


def enc_ack(stream, nxt):
    return bytes([stream]) + struct.pack("<Q", nxt)


def dec_ack(p):
    if len(p) < 9:
        raise ProtoError("bad ack")
    return p[0], struct.unpack_from("<Q", p, 1)[0]


def err_from(payload):
    t = dec_tlv(payload)
    return AgentError(t.get("code", "EINTERNAL"), t.get("msg", ""), t.geti("errno"))
