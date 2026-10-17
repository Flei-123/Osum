#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/platte/check.py -- the text plate follows the ink (r1062).

    check.py <low.png> <low.serial> <full.png>

low  = window_alpha=20 picture, full = window_alpha=100 picture of the SAME state.
For every window label (rect from the `wlib: text` trace) the pixels split into
  ink    : differ from the dominant colour of the rect in the full picture,
  halo   : within 2 px (Chebyshev) of ink,
  ground : the rest of the rect.
Halo pixels must be equal in both pictures (opaque plate); ground pixels must differ (mixed with the backdrop).
Prints: labels=N halo=N halo_same=N ground=N ground_diff=N corner=N corner_diff=N
corner = the top-left pixel of each label rect (never ink).
"""
import importlib.util
import os
import re
import sys
from collections import Counter

from PIL import Image

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("glascheck", os.path.join(here, "..", "themestore", "glascheck.py"))
gc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gc)


def main(low, serial, full):
    a = Image.open(low).convert("RGB")
    b = Image.open(full).convert("RGB")
    if a.size != b.size:
        print("size mismatch", a.size, b.size)
        return 1
    roh = open(serial, "rb").read().decode("latin1")
    marke = "settings: rect name=waa "
    schnitt = roh.rfind(marke)
    schwanz = roh[schnitt:] if schnitt >= 0 else roh
    f = re.findall(r"wlib: font ui px=(\d+) asc=(\d+) h=(\d+)", roh)
    asc, desc = (int(f[-1][1]), int(f[-1][2]) - int(f[-1][1])) if f else (16, 6)
    zeilen = [m for m in (gc.FENSTERTEXT.search(ln) for ln in schwanz.splitlines()) if m]
    if not zeilen:
        print("platte KEINE Beschriftung im Mitschnitt")
        return 1
    win = Counter(int(m.group(1)) for m in zeilen).most_common(1)[0][0]
    letzte = {}
    for m in zeilen:
        if int(m.group(1)) == win and m.group(10).strip():
            letzte[(m.group(2), m.group(10))] = m
    labels = halo = halo_same = ground = ground_diff = corner = corner_diff = 0
    for m in letzte.values():
        x0 = int(m.group(8)) + int(m.group(3))
        y0 = int(m.group(9)) + int(m.group(4)) - asc
        x1 = min(x0 + int(m.group(7)), b.size[0])
        y1 = min(int(m.group(9)) + int(m.group(4)) + desc, b.size[1])
        if x0 >= x1 or y0 >= y1 or x0 < 0 or y0 < 0:
            continue
        pts = [(x, y) for y in range(y0, y1) for x in range(x0, x1)]
        bgc = Counter(b.getpixel(p) for p in pts).most_common(1)[0][0]
        ink = set(p for p in pts if b.getpixel(p) != bgc)
        if not ink:
            continue
        labels += 1
        corner += 1
        corner_diff += int(a.getpixel((x0, y0)) != b.getpixel((x0, y0)))
        for p in pts:
            near = any((p[0] + dx, p[1] + dy) in ink for dx in range(-2, 3) for dy in range(-2, 3))
            same = a.getpixel(p) == b.getpixel(p)
            if near:
                halo += 1
                halo_same += int(same)
            else:
                ground += 1
                ground_diff += int(not same)
    print("labels=%d halo=%d halo_same=%d ground=%d ground_diff=%d corner=%d corner_diff=%d"
          % (labels, halo, halo_same, ground, ground_diff, corner, corner_diff))
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:4]))
