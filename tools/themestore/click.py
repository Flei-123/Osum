#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    click.py <x,y> [<x,y> ...]      > monitorbefehle.txt
    click.py '<x,y>><x2,y2>[><x3,y3>...]'   ein ZUG statt eines Klicks
"""
import sys


def go(x, y):
    out = ["mouse_move -120 -120"] * 12
    dx, dy = x, y
    while dx > 0 or dy > 0:
        sx, sy = min(dx, 120), min(dy, 120)
        out.append("mouse_move %d %d" % (sx, sy))
        dx -= sx
        dy -= sy
    return out


def drag(points):
    x0, y0 = points[0]
    out = go(x0, y0)
    out += ["warte 1", "mouse_button 1", "warte 1"]
    for (x1, y1) in points[1:]:
        dx, dy = x1 - x0, y1 - y0
        schritte = max(abs(dx), abs(dy), 1)
        schritte = min(max((schritte + 39) // 40, 1), 40)
        vx, vy = 0, 0
        for i in range(1, schritte + 1):
            nx, ny = dx * i // schritte, dy * i // schritte
            out.append("mouse_move %d %d" % (nx - vx, ny - vy))
            vx, vy = nx, ny
        out.append("warte 1")
        x0, y0 = x1, y1
    out += ["warte 1", "mouse_button 0", "warte 2"]
    return out


def typed(text):
    out = []
    for ch in text:
        key = "spc" if ch == " " else ch
        out += ["sendkey " + key, "warte 1"]
    out.append("warte 2")
    return out


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    lines = []
    for p in argv[1:]:
        if p.startswith("type:"):
            lines += typed(p[5:])
            continue
        if ">" in p:
            lines += drag([tuple(int(v) for v in t.split(","))
                           for t in p.split(">")])
            continue
        x, y = (int(v) for v in p.split(","))
        lines += go(x, y)
        lines += ["warte 1", "mouse_button 1", "mouse_button 0", "warte 2"]
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
