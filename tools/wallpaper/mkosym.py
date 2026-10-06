#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/wallpaper/mkosym.py -- turn a photo into the wallpaper format of the
desktop (`/etc/wallpaper`, magic "OSYM": 12 octet head = magic, width, height
as little-endian u32, then B, G, R, A per pixel).

    mkosym.py <in.jpg|png> <out.osym> [width height]

Default 480 x 270 (16:9, 518 412 octets): the desktop's limit is
IMAGE_MAX_W x IMAGE_MAX_H (kernel/user/desktop.fi). The photo is scaled with
Lanczos and cropped to the aspect ratio of width:height first.
"""
import struct
import sys
from PIL import Image

def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    w = int(sys.argv[3]) if len(sys.argv) > 3 else 480
    h = int(sys.argv[4]) if len(sys.argv) > 4 else 270
    im = Image.open(src).convert("RGB")
    sw, sh = im.size
    want = w / h
    if sw / sh > want:
        nw = int(round(sh * want)); x0 = (sw - nw) // 2
        im = im.crop((x0, 0, x0 + nw, sh))
    else:
        nh = int(round(sw / want)); y0 = (sh - nh) // 2
        im = im.crop((0, y0, sw, y0 + nh))
    im = im.resize((w, h), Image.LANCZOS)
    raw = im.tobytes()
    out = bytearray(b"OSYM" + struct.pack("<II", w, h))
    for i in range(0, len(raw), 3):
        out += bytes((raw[i + 2], raw[i + 1], raw[i], 255))
    open(dst, "wb").write(out)
    print("%s: %dx%d, %d octets" % (dst, w, h, len(out)))
    return 0

if __name__ == "__main__":
    sys.exit(main())
