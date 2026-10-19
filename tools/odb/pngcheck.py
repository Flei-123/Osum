#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""pngcheck.py <file.png> <w> <h> -- verify an ODB `shot pattern=1` PNG pixel-exactly.

Decodes the PNG with zlib + unfilter (all five filter types) and compares every pixel with the
agent's test image formula (pat_pixel in kernel/user/odbd.fi) evaluated for the 320x200 source.
Exit 0 = identical, 1 = pixel mismatch, 2 = not a valid PNG of the expected size.
"""
import struct
import sys
import zlib

SRC_W, SRC_H = 320, 200


def pat_pixel(x, y, w, h):
    if y * 4 < h:
        return (x * 255 // w, y * 255 // h, 128)
    if y * 2 < h:
        return (30, 60, 90) if (((x >> 4) + (y >> 4)) & 1) == 0 else (200, 200, 200)
    if y * 4 < 3 * h:
        hs = ((x * 73856093) ^ (y * 19349663)) & 0xFFFFFF
        return (hs & 255, (hs >> 8) & 255, (hs >> 16) & 255)
    return ((x * 3) & 255, (x >> 2) & 255, 77)


def decode(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("no PNG signature")
    pos, idat, ihdr = 8, b"", None
    while pos < len(data):
        n, typ = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        crc = struct.unpack(">I", data[pos + 8 + n:pos + 12 + n])[0]
        if zlib.crc32(typ + body) & 0xFFFFFFFF != crc:
            raise ValueError("bad CRC in chunk %r" % typ)
        if typ == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", body)
        elif typ == b"IDAT":
            idat += body
        pos += 12 + n
    if ihdr is None:
        raise ValueError("no IHDR")
    w, h, depth, ctype = ihdr[0], ihdr[1], ihdr[2], ihdr[3]
    if depth != 8 or ctype != 2:
        raise ValueError("not 8-bit RGB (depth %d type %d)" % (depth, ctype))
    raw = zlib.decompress(idat)
    stride = w * 3
    if len(raw) != h * (stride + 1):
        raise ValueError("raw size %d != %d" % (len(raw), h * (stride + 1)))
    rows, prev = [], bytearray(stride)
    for y in range(h):
        f = raw[y * (stride + 1)]
        cur = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = cur[i - 3] if i >= 3 else 0
            b = prev[i]
            c = prev[i - 3] if i >= 3 else 0
            if f == 1:
                cur[i] = (cur[i] + a) & 255
            elif f == 2:
                cur[i] = (cur[i] + b) & 255
            elif f == 3:
                cur[i] = (cur[i] + ((a + b) >> 1)) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                cur[i] = (cur[i] + pr) & 255
            elif f != 0:
                raise ValueError("bad filter %d" % f)
        rows.append(cur)
        prev = cur
    return w, h, rows


def main():
    path, ew, eh = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    mask = (255 >> int(sys.argv[4])) << int(sys.argv[4]) if len(sys.argv) > 4 else 255   # optional: colour bits dropped by `shot --quant`
    try:
        w, h, rows = decode(open(path, "rb").read())
    except Exception as e:  # noqa: BLE001
        print("invalid PNG: %s" % e)
        return 2
    if (w, h) != (ew, eh):
        print("size %dx%d, expected %dx%d" % (w, h, ew, eh))
        return 2
    bad = 0
    for dy in range(h):
        sy = dy * SRC_H // h
        for dx in range(w):
            exp = tuple(c & mask for c in pat_pixel(dx * SRC_W // w, sy, SRC_W, SRC_H))
            got = tuple(rows[dy][dx * 3:dx * 3 + 3])
            if got != exp:
                bad += 1
                if bad <= 3:
                    print("pixel (%d,%d): got %s expected %s" % (dx, dy, got, exp))
    print("%dx%d, %d wrong pixels of %d" % (w, h, bad, w * h))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
