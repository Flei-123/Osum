#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    ppm2png.py <source.ppm> <target.png>
"""

import struct
import sys
import zlib


def ppm_read(path_2):
    with open(path_2, "rb") as f:
        roh = f.read()
    if not roh.startswith(b"P6"):
        raise SystemExit("ppm2png: kein P6-PPM: %s" % path_2)
    at = 2
    felder = []
    while len(felder) < 3:
        while at < len(roh) and roh[at:at + 1].isspace():
            at += 1
        if roh[at:at + 1] == b"#":
            while at < len(roh) and roh[at:at + 1] != b"\n":
                at += 1
            continue
        begin = at
        while at < len(roh) and not roh[at:at + 1].isspace():
            at += 1
        felder.append(int(roh[begin:at]))
    at += 1
    b, h, up = felder
    if up != 255:
        raise SystemExit("ppm2png: nur 8 Bit je Kanal, nicht %d" % up)
    data = roh[at:at + b * h * 3]
    if len(data) < b * h * 3:
        raise SystemExit("ppm2png: %d Oktette zu wenig"
                         % (b * h * 3 - len(data)))
    return b, h, data


def chunk(art, nutz):
    return (struct.pack(">I", len(nutz)) + art + nutz
            + struct.pack(">I", zlib.crc32(art + nutz) & 0xFFFFFFFF))


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    b, h, data = ppm_read(argv[1])

    rows = bytearray()
    schritt = b * 3
    for y in range(h):
        z = data[y * schritt:(y + 1) * schritt]
        rows.append(1)
        rows += z[:3]
        vorher = memoryview(z)[:-3]
        now = memoryview(z)[3:]
        rows += bytes((a - c) & 255 for a, c in zip(now, vorher))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", b, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    png += chunk(b"IEND", b"")
    with open(argv[2], "wb") as f:
        f.write(png)
    print("ppm2png: %dx%d -> %s (%d Oktette)"
          % (b, h, argv[2], len(png)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
