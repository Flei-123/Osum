#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    hover.py <x,y>            > monitorbefehle.txt
"""
import sys


def go(x, y):
    out = ["mouse_move -120 -120"] * 6
    dx, dy = x, y
    while dx > 0 or dy > 0:
        sx, sy = min(dx, 120), min(dy, 120)
        out.append("mouse_move %d %d" % (sx, sy))
        dx -= sx
        dy -= sy
    out.append("warte 1")
    return out


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    lines = []
    for p in argv[1:]:
        x, y = (int(v) for v in p.split(","))
        lines += go(x, y)
    lines.append("warte 2")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
