#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/netview/ink.py -- does a glyph stand where the panel says it drew it?

usage: ink.py <screen.ppm> <x> <y> [box] [min_pixels]
The quick-settings tiles paint Fluent vector glyphs (cv_glyph), not the old
hand-drawn tile-*.txt drawings, so a pixel-for-pixel compare no longer applies.
This counts the pixels in the middle of the glyph box that differ from the plate
colour (the pixel at the box corner). Prints "ok N" (exit 0) or "empty N" (exit 1).
"""
import sys


def main(argv):
    path, x, y = argv[1], int(argv[2]), int(argv[3])
    box = int(argv[4]) if len(argv) > 4 else 12
    need = int(argv[5]) if len(argv) > 5 else 6
    d = open(path, "rb").read()
    f, at = [], 2
    while len(f) < 3:
        while d[at:at + 1].isspace():
            at += 1
        s = at
        while not d[at:at + 1].isspace():
            at += 1
        f.append(int(d[s:at]))
    w, h = f[0], f[1]
    raw = d[at + 1:]

    def px(a, b):
        o = (b * w + a) * 3
        return raw[o], raw[o + 1], raw[o + 2]

    bg = px(x + 1, y + 1)
    n = 0
    for b in range(y + 4, y + 4 + box):
        for a in range(x + 4, x + 4 + box):
            if 0 <= a < w and 0 <= b < h:
                c = px(a, b)
                if abs(c[0] - bg[0]) + abs(c[1] - bg[1]) + abs(c[2] - bg[2]) > 90:
                    n += 1
    print(("ok %d" if n >= need else "empty %d") % n)
    return 0 if n >= need else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
