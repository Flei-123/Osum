#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    pixel.py <image.ppm>                 die haeufigste Color
    pixel.py <image.ppm> --top 5         die fuenf haeufigsten mit Anteil
    pixel.py <image.ppm> --has RRGGBB    Beendigungscode 0, if es sie gibt
    pixel.py <image.ppm> --share RRGGBB  ihr Anteil in ZEHNTELPROZENT
    pixel.py <image.ppm> --at X Y        die Color an genau dieser Pos
"""
import sys
from collections import Counter
import os
sys.path.insert(0, os.path.join(os.environ.get("FIRN", "/root/firn"), "tools/testkit"))
from testkit import read_ppm


def census(px):
    c = Counter()
    for k in range(0, len(px), 3):
        c[(px[k], px[k + 1], px[k + 2])] += 1
    return c


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    w, h, px = read_ppm(sys.argv[1])
    total = w * h
    c = census(px)
    args = sys.argv[2:]
    if args and args[0] == "--has":
        want = args[1].lower().lstrip("#")
        col = (int(want[0:2], 16), int(want[2:4], 16), int(want[4:6], 16))
        n = c.get(col, 0)
        print("%06x %d" % (int(want, 16), n))
        return 0 if n > 0 else 1
    if args and args[0] == "--share":
        want = args[1].lower().lstrip("#")
        col = (int(want[0:2], 16), int(want[2:4], 16), int(want[4:6], 16))
        print("%d" % (1000 * c.get(col, 0) // total))
        return 0
    if args and args[0] == "--at":
        x, y = int(args[1]), int(args[2])
        k = (y * w + x) * 3
        print("%02x%02x%02x" % (px[k], px[k + 1], px[k + 2]))
        return 0
    top = 1
    if args and args[0] == "--top":
        top = int(args[1])
    out = []
    for col, n in c.most_common(top):
        out.append("%02x%02x%02x:%.1f%%"
                   % (col[0], col[1], col[2], 100.0 * n / total))
    print(" ".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
