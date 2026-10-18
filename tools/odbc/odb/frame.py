# SPDX-License-Identifier: GPL-2.0-only
"""ODB wire frame codec + resynchronising stream decoder.

Frame (little endian):
  magic 'ODB1'(4) | ver u8 | type u8 | flags u16 | id u32 | len u32 (<= 64 KiB) | payload | crc32 u32
The CRC32 (zlib) covers everything from magic up to and including the payload.
"""
import struct
import zlib

MAGIC = b"ODB1"
VERSION = 1
MAX_PAYLOAD = 64 * 1024
HDR = struct.Struct("<4sBBHII")
HDR_LEN = HDR.size  # 16
CRC_LEN = 4
OVERHEAD = HDR_LEN + CRC_LEN

REQ, RESP, DATA, END, ERR, PING = 1, 2, 3, 4, 5, 6
TYPE_NAMES = {REQ: "REQ", RESP: "RESP", DATA: "DATA", END: "END", ERR: "ERR", PING: "PING"}


class FrameError(ValueError):
    pass


class Frame:
    __slots__ = ("type", "id", "flags", "payload", "ver")

    def __init__(self, type, id=0, payload=b"", flags=0, ver=VERSION):
        self.type = type
        self.id = id
        self.payload = bytes(payload)
        self.flags = flags
        self.ver = ver

    def __eq__(self, o):
        return (isinstance(o, Frame) and self.type == o.type and self.id == o.id
                and self.payload == o.payload and self.flags == o.flags and self.ver == o.ver)

    def __repr__(self):
        return "Frame(%s id=%d flags=%#x len=%d)" % (
            TYPE_NAMES.get(self.type, self.type), self.id, self.flags, len(self.payload))


def encode(f):
    if len(f.payload) > MAX_PAYLOAD:
        raise FrameError("payload too large: %d" % len(f.payload))
    head = HDR.pack(MAGIC, f.ver, f.type, f.flags, f.id, len(f.payload))
    body = head + f.payload
    return body + struct.pack("<I", zlib.crc32(body) & 0xFFFFFFFF)


class Decoder:
    """Feed arbitrary byte chunks, get complete frames. On garbage / bad CRC it
    skips to the next magic (resync) and counts what it dropped."""

    def __init__(self):
        self.buf = bytearray()
        self.garbage = 0     # bytes skipped while hunting for a magic
        self.bad_crc = 0
        self.bad_hdr = 0     # header with impossible len / ver

    def feed(self, data):
        self.buf += data
        out = []
        buf = self.buf
        while True:
            i = buf.find(MAGIC)
            if i < 0:
                # keep a possible magic prefix at the tail
                keep = 0
                for k in (3, 2, 1):
                    if buf.endswith(MAGIC[:k]):
                        keep = k
                        break
                drop = len(buf) - keep
                if drop > 0:
                    self.garbage += drop
                    del buf[:drop]
                break
            if i > 0:
                self.garbage += i
                del buf[:i]
            if len(buf) < HDR_LEN:
                break
            _m, ver, typ, flags, fid, ln = HDR.unpack_from(buf, 0)
            if ln > MAX_PAYLOAD or ver == 0:
                self.bad_hdr += 1
                del buf[:1]
                continue
            total = HDR_LEN + ln + CRC_LEN
            if len(buf) < total:
                break
            (crc,) = struct.unpack_from("<I", buf, HDR_LEN + ln)
            if zlib.crc32(bytes(buf[:HDR_LEN + ln])) & 0xFFFFFFFF != crc:
                self.bad_crc += 1
                del buf[:1]       # resync: maybe a magic inside the bad frame
                continue
            out.append(Frame(typ, fid, bytes(buf[HDR_LEN:HDR_LEN + ln]), flags, ver))
            del buf[:total]
        return out
