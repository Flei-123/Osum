#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys, zlib, struct


def read_ppm(p):
    d = open(p, "rb").read()
    parts = []
    i = 0
    while len(parts) < 4:
        while i < len(d) and d[i:i + 1].isspace():
            i += 1
        if d[i:i + 1] == b"#":
            while d[i:i + 1] not in (b"\n", b""):
                i += 1
            continue
        s = i
        while i < len(d) and not d[i:i + 1].isspace():
            i += 1
        parts.append(d[s:i])
    i += 1
    w, h = int(parts[1]), int(parts[2])
    return w, h, d[i:i + w * h * 3]


def chunk(typ, data):
    c = typ + data
    return (struct.pack(">I", len(data)) + c
            + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF))


def main(src, dst):
    w, h, px = read_ppm(src)
    raw = b"".join(b"\x00" + px[y * w * 3:(y + 1) * w * 3] for y in range(h))
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 6))
           + chunk(b"IEND", b""))
    open(dst, "wb").write(png)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
