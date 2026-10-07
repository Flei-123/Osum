#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/design/measure.py -- numbers for the design audit (r399).

    measure.py <before-dir> <after-dir>

Both directories hold the photographs of tools/design/audit.sh (01-schreibtisch.png,
02-startmenue.png, ...).  Every number is read OUT OF THE PICTURES (or the
serial log next to them), none is typed in:

  wallpaper   share of horizontally equal neighbour pixels in the tree line crop
              (nearest-neighbour upscaling repeats every source pixel 2-3 times:
              a high share = blocks; a smooth bilinear picture has a low one)
  corner      pixels outside the rounded corner arc of the start menu that differ
              from the picture WITHOUT the menu (a frosted rectangle behind a
              rounded window shows up here: the grey halo)
  selection   contrast of the plate (selected row) against the list ground and of
              the text against the plate, WCAG 2.x
  frame       `bildzeit:` of the run (mean frame time in microseconds, frames over 16 ms)
"""
import os
import re
import sys

from PIL import Image


def lum(c):
    def f(v):
        v /= 255.0
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = c[:3]
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def contrast(a, b):
    la, lb = lum(a), lum(b)
    if la < lb:
        la, lb = lb, la
    return (la + 0.05) / (lb + 0.05)


def wallpaper_blockiness(path):
    im = Image.open(path).convert("RGB")
    # the tree line of the sea photograph, right side, below the menu and the bar
    box = (960, 380, 1280, 560)
    c = im.crop(box)
    w, h = c.size
    px = c.load()
    same = tot = 0
    for y in range(h):
        for x in range(w - 1):
            tot += 1
            if px[x, y] == px[x + 1, y]:
                same += 1
    return same / tot


def corner_halo(menu_png, base_png, x0=8, y0=300, r=12):
    m = Image.open(menu_png).convert("RGB")
    b = Image.open(base_png).convert("RGB")
    mp, bp = m.load(), b.load()
    n = 0
    tot = 0
    for dy in range(r):
        for dx in range(r):
            # centre of the corner circle is (r, r) from the corner of the window
            ddx = 2 * (r - dx) - 1
            ddy = 2 * (r - dy) - 1
            if ddx * ddx + ddy * ddy > 4 * r * r + 8 * r:  # clearly outside the arc
                tot += 1
                if mp[x0 + dx, y0 + dy] != bp[x0 + dx, y0 + dy]:
                    n += 1
    return n, tot


def frame(dirpath):
    p = os.path.join(dirpath, "serial.txt")
    if not os.path.exists(p):
        return None
    last = None
    for ln in open(p, "rb"):
        m = re.search(rb"bildzeit: n=(\d+)\s+mittel=(\d+) us\s+max=(\d+) us\s+ueber16=(\d+)", ln)
        if m:
            last = tuple(int(g) for g in m.groups())
    return last


def main(argv):
    a, b = argv[0], argv[1]
    for tag, d in (("before", a), ("after", b)):
        print("== %s: %s" % (tag, d))
        w = os.path.join(d, "01-schreibtisch.png")
        if os.path.exists(w):
            print("  wallpaper equal-neighbour share  %.3f" % wallpaper_blockiness(w))
        m = os.path.join(d, "02-startmenue.png")
        if os.path.exists(m) and os.path.exists(w):
            n, tot = corner_halo(m, w)
            print("  corner halo pixels (outside arc)  %d of %d" % (n, tot))
        f = frame(d)
        if f:
            print("  frame time  n=%d mean=%d us max=%d us over16ms=%d" % f)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
