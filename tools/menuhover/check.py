#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/menuhover/check.py -- pixel checks for the start menu under the mouse.

    check.py <capture-dir> <expect: sharp|smeared>

The capture directory comes from tools/design/capture.sh with the script of
run.sh. Pictures: `01-menu` (menu open, pointer far away) and `h<N>-...`
(pointer on row N, ...). The checks use the pictures and the serial report only:

  1. outside the pointer sprite, NOTHING inside the menu window may differ
     from the picture without hover (count of points that differ by more
     than 12 levels in one channel);
  2. the row under the pointer keeps its sharpness: the sum of the absolute
     horizontal differences of the row's rectangle is at least 90 % of the
     value without hover (blur takes the text's edges away).

`expect=smeared` is the counter-proof (kernel run with `noglasgrow`, the
rule that grows the dirty area is off): the same checks MUST fail there,
otherwise they never measured anything.
"""
import re
import sys

from PIL import Image

d = sys.argv[1]
expect = sys.argv[2]
ser = open(d + "/serial.txt", "rb").read().decode("latin1")

geom = re.findall(r"launcher: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser)
if not geom:
    print("NOGEOM")
    sys.exit(2)
wx, wy, ww, wh = (int(v) for v in geom[-1])
rows = {}
for m in re.finditer(r"launcher: rect id=2 kind=5 x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser):
    rows["list"] = tuple(int(v) for v in m.groups())
lx, ly, lw, lh = rows["list"]
# the list's rectangle is relative to the window's inner origin; the same
# conversion as tools/design/drive.py (geom + frame 2 + title bar 22)
ox, oy = wx + 2, wy + 22
rowh = 52
base = Image.open(d + "/01-menu.ppm").convert("RGB")
bpx = base.load()


def sharp(img, x0, y0, x1, y1):
    p = img.load()
    s = 0
    for y in range(y0, y1):
        for x in range(x0 + 1, x1):
            a, b = p[x - 1, y], p[x, y]
            s += abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])
    return s


bad_total = 0
worst_ratio = 1.0
for n in range(5):
    import glob
    fs = glob.glob("%s/h%d-*.ppm" % (d, n))
    if not fs:
        print("MISSING h%d" % n)
        sys.exit(2)
    img = Image.open(fs[0]).convert("RGB")
    p = img.load()
    # where was the pointer: the middle of row n
    px = ox + lx + lw // 2
    py = oy + ly + n * rowh + rowh // 2
    bad = 0
    for y in range(wy, min(wy + wh, img.size[1])):
        for x in range(wx, wx + ww):
            if px - 6 <= x <= px + 22 and py - 6 <= y <= py + 30:
                continue                    # the pointer sprite
            a, b = bpx[x, y], p[x, y]
            if max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2])) > 12:
                bad += 1
    r0 = sharp(base, ox + lx, oy + ly + n * rowh, ox + lx + lw, oy + ly + (n + 1) * rowh)
    r1 = sharp(img, ox + lx, oy + ly + n * rowh, ox + lx + lw, oy + ly + (n + 1) * rowh)
    ratio = r1 / r0 if r0 else 1.0
    print("row %d: pointer %d,%d  changed points outside the pointer: %d  sharpness %.0f%%"
          % (n, px, py, bad, ratio * 100))
    bad_total += bad
    worst_ratio = min(worst_ratio, ratio)

ok = bad_total == 0 and worst_ratio >= 0.90
print("TOTAL changed=%d worst_sharpness=%.0f%% -> %s" % (bad_total, worst_ratio * 100,
      "SHARP" if ok else "SMEARED"))
if expect == "sharp":
    sys.exit(0 if ok else 1)
sys.exit(0 if not ok else 1)
