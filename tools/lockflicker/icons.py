#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/lockflicker/icons.py <run dir> <lock|glogin> <width> <height> <scale> [picture=base]

W-LOGIN, task B: the symbol in every square tile (eye, unlock/sign-in arrow, power, network) sits in the MIDDLE of its tile.
Tiles: serial `<app>: rect ... w=<36*scale> h=<36*scale>` (+ `wlib: eyerect x= y=` for the eye of the sign-in screen).
Per tile: the face colour is the median colour of the tile's inner box (inset 5 * scale); the symbol is every pixel that differs from it
by more than 60 (sum of channel differences). Measured: centre of the symbol's bounding box and its pixel centroid against the tile centre.
Prints one line per tile; `ICONS ok=N bad=M worst=<px>`; exit 0 = every bounding-box centre within 1 px of the tile centre in x and y, 1 = not, 2 = no tile found.
"""
import re, sys

def read_ppm(path):
    d = open(path, "rb").read()
    m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+255\s", d)
    return int(m.group(1)), int(m.group(2)), d[m.end():]

def main():
    run, app, W, H, S = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
    pic = sys.argv[6] if len(sys.argv) > 6 else "base"
    import numpy as np
    ser = open(run + "/serial.txt", errors="replace").read().splitlines()
    tiles = {}
    pat = re.compile(r"%s: rect id=(\d+) kind=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % app)
    for l in ser:
        m = pat.search(l)
        if m:
            i, k, x, y, w, h = map(int, m.groups())
            if w == 36 * S and h == 36 * S:
                tiles["id%d" % i] = (x, y)
    for l in ser:
        m = re.search(r"wlib: eyerect x=(\d+) y=(\d+)", l)
        if m:
            tiles["eye"] = (int(m.group(1)), int(m.group(2)))
    if not tiles:
        print("ICONS no tile found")
        return 2
    w, h, d = read_ppm("%s/%s.ppm" % (run, pic))
    img = np.frombuffer(d, dtype=np.uint8).reshape(h, w, 3).astype(np.int32)
    side = 36 * S
    ins = 5 * S
    ok = bad = 0
    worst = 0.0
    for name, (x, y) in sorted(tiles.items()):
        if x < 0 or y < 0 or x + side > w or y + side > h:
            print("  FAIL  %s: tile outside the picture (%d,%d)" % (name, x, y))
            bad += 1
            continue
        box = img[y + ins:y + side - ins, x + ins:x + side - ins]
        face = np.median(box.reshape(-1, 3), axis=0)
        diff = np.abs(box - face).sum(axis=2)
        m = diff > 60
        if m.sum() < 8:
            print("  FAIL  %s: no symbol found in the tile at (%d,%d)" % (name, x, y))
            bad += 1
            continue
        ys, xs = np.nonzero(m)
        cx = (xs.min() + xs.max() + 1) / 2.0 + ins - side / 2.0
        cy = (ys.min() + ys.max() + 1) / 2.0 + ins - side / 2.0
        wgt = diff[m].astype(np.float64)
        mx = (xs * wgt).sum() / wgt.sum() + 0.5 + ins - side / 2.0
        my = (ys * wgt).sum() / wgt.sum() + 0.5 + ins - side / 2.0
        dev = max(abs(cx), abs(cy))
        worst = max(worst, dev)
        good = abs(cx) <= 1.0 and abs(cy) <= 1.0
        ok += good
        bad += not good
        print("  %s  %s tile (%d,%d) %dx%d: symbol bbox %dx%d, bbox centre off by (%+.1f,%+.1f) px, centroid off by (%+.1f,%+.1f) px"
              % ("OK  " if good else "FAIL", name, x, y, side, side, xs.max() - xs.min() + 1, ys.max() - ys.min() + 1, cx, cy, mx, my))
    print("ICONS ok=%d bad=%d worst=%.1f" % (ok, bad, worst))
    return 1 if bad else 0

sys.exit(main())
