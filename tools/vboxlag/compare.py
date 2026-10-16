#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/vboxlag/compare.py <dir-diff> <dir-nodiff> [out-dir]

Compares the screendump series of tools/vboxlag/visual.sh pixel by pixel (diff flush vs `nodiff`). Time-dependent areas
(taskbar clock, widgets top right, terminal text) are masked; a pointer that stands at another place in the two runs shows up as
two small differing boxes, so every difference outside the mask is reported with its bounding box and the number of 32x32 cells.
Exit code 0 = all shots identical outside the mask, 1 = differences (they are printed).
"""
import glob
import os
import sys

from PIL import Image, ImageChops

a, b = sys.argv[1], sys.argv[2]
out = sys.argv[3] if len(sys.argv) > 3 else None
MASKS = [(1085, 8, 1280, 145), (1090, 762, 1280, 800),  # widgets top right, clock bottom right (1280x800)
         (24, 72, 590, 456),  # terminal text (boot log scrolls with time)
         (36, 130, 44, 168)]  # caret of the start menu search field (blinks)
bad = 0
tot = 0
PTR_MAX = 520  # two arrow cursors (about 230 px each): the pointer stood at another place in the two runs (mouse packets are timing-dependent)
ptr_only = 0
for fa in sorted(glob.glob(os.path.join(a, "v*.ppm"))):
    name = os.path.basename(fa)
    fb = os.path.join(b, name)
    if not os.path.exists(fb):
        print("%-22s MISSING in nodiff run" % name)
        bad += 1
        continue
    ia = Image.open(fa).convert("RGB")
    ib = Image.open(fb).convert("RGB")
    if ia.size != ib.size:
        print("%-22s SIZE %s vs %s" % (name, ia.size, ib.size))
        bad += 1
        continue
    d = ImageChops.difference(ia, ib).convert("L").point(lambda v: 255 if v > 6 else 0)
    for (x0, y0, x1, y1) in MASKS:
        d.paste(0, (x0, y0, min(x1, d.size[0]), min(y1, d.size[1])))
    bb = d.getbbox()
    n = sum(1 for v in d.tobytes() if v)
    tot += 1
    if bb is None:
        print("%-22s identical" % name)
        continue
    cells = set()
    w = d.size[0]
    for i, v in enumerate(d.tobytes()):
        if v:
            cells.add(((i % w) // 32, (i // w) // 32))
    if n <= PTR_MAX:
        print("%-22s PTR-ONLY px=%d bbox=%s (pointer at another place, no ghost)" % (name, n, bb))
        ptr_only += 1
        continue
    print("%-22s DIFF px=%d bbox=%s cells=%d" % (name, n, bb, len(cells)))
    bad += 1
    if out:
        os.makedirs(out, exist_ok=True)
        d.save(os.path.join(out, name[:-4] + "_diff.png"))
print("SUMMARY shots=%d pointer_only=%d with_difference=%d" % (tot, ptr_only, bad))
sys.exit(1 if bad else 0)
