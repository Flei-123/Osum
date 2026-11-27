#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

from PIL import Image

PASS = FAIL = 0
TOL = 24
MAX_MID_DELTA = 1.0


def check(cond, msg):
    global PASS, FAIL
    PASS += cond
    FAIL += not cond
    print(("  OK    " if cond else "  FAIL  ") + msg)


def dist(a, b):
    return max(abs(a[i] - b[i]) for i in range(3))


def bar_extent(px, x, y, h, ref):
    top = y
    while top > 0 and dist(px[x, top - 1], ref) <= TOL:
        top -= 1
    bot = y
    while bot < h - 1 and dist(px[x, bot + 1], ref) <= TOL:
        bot += 1
    return top, bot


def window_lines(path):
    seen = {}
    for line in open(path, errors="replace"):
        m = re.search(r"wm: fen i=(\d+).* tx=(\d+).* ic=(\d+),(\d+),(\d+)(?:.* sy=(\d))?", line)
        if m:
            seen[int(m.group(1))] = tuple(int(v or 0) for v in m.groups()[1:])
    return list(seen.values())


def main():
    im = Image.open(sys.argv[1]).convert("RGB")
    wins = window_lines(sys.argv[2])
    px = im.load()
    W, H = im.size
    check(len(wins) >= 1, "%d window(s) report an icon word (ic=size,x,y)" % len(wins))
    check(any(w[4] == 1 for w in wins), "at least one window shows a real program symbol (sy=1)")
    for tx, size, ix, iy, _sy in wins:
        print("        icon size=%d at %d,%d, title text starts at %d" % (size, ix, iy, tx))
        check(size > 0 and ix + size <= tx, "icon x %d..%d ends before the title text at %d" % (ix, ix + size, tx))
        probe = (ix + size + 3, iy + size // 2)
        ref = px[probe]
        top, bot = bar_extent(px, probe[0], probe[1], H, ref)
        ink = [(x, y) for y in range(max(top, iy - 2), min(bot, iy + size + 2) + 1)
               for x in range(ix - 2, ix + size + 2) if 0 <= x < W and dist(px[x, y], ref) > 40]
        check(len(ink) >= size * size // 4, "the icon wrote %d pixels" % len(ink))
        if not ink:
            continue
        cy = (min(p[1] for p in ink) + max(p[1] for p in ink)) / 2.0
        mid = (top + bot) / 2.0
        check(abs(cy - mid) <= MAX_MID_DELTA, "icon middle %.1f vs bar middle %.1f (bar rows %d..%d)" % (cy, mid, top, bot))
        left = min(p[0] for p in ink)
        check(left <= ix + 1, "icon ink starts at the left slot (first column %d, slot %d)" % (left, ix))
    print("PICTURE: %d passed, %d failed" % (PASS, FAIL))
    return FAIL


if __name__ == "__main__":
    sys.exit(main())
