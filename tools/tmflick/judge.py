#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/tmflick/judge.py <dir> <prefix> [--max N] -- W-FLICKER: count frames whose STATIC regions differ from the per-pixel median of the series.

Static regions of the task manager window (1920x1080 wigapp, window at 21,17 .. 983,619): the navigation rail text rows and the
title bar are never repainted with different content, so any pixel change there between two screendumps is a half-painted picture the
window server composed (the in-place paint cleared the window and the screendump caught it before the widgets came back).
"""
import glob
import sys

import numpy as np


def load(p):
    with open(p, "rb") as f:
        d = f.read()
    parts = d.split(b"\n", 3)
    w, h = (int(v) for v in parts[1].split())
    return np.frombuffer(parts[3], dtype=np.uint8).reshape(h, w, 3).astype(np.int16)


REGIONS = {
    "rail": (34, 50, 204, 360),
    "title": (24, 20, 960, 36),
    "head": (230, 190, 960, 215),
}


def main():
    d, pre = sys.argv[1], sys.argv[2]
    mx = 0
    if "--max" in sys.argv:
        mx = int(sys.argv[sys.argv.index("--max") + 1])
    if "--regions" in sys.argv:
        keep = sys.argv[sys.argv.index("--regions") + 1].split(",")
        for k in list(REGIONS):
            if k not in keep:
                del REGIONS[k]
    files = sorted(glob.glob("%s/%s-*.ppm" % (d, pre)))
    ims = [load(f) for f in files]
    bad = 0
    worst = 0
    ref = {}
    for name, (x0, y0, x1, y1) in REGIONS.items():
        ref[name] = np.median(np.stack([im[y0:y1, x0:x1] for im in ims]), axis=0)
    for im in ims:
        tot = 0
        for name, (x0, y0, x1, y1) in REGIONS.items():
            dd = np.abs(im[y0:y1, x0:x1] - ref[name]).sum(axis=2)
            tot += int((dd > 24).sum())
        worst = max(worst, tot)
        if tot > 40:
            bad += 1
    distinct = len(set(im[40:600, 220:960].tobytes() for im in ims))
    print("tmflick: frames=%d distinct_content=%d flicker=%d worst_px=%d" % (len(files), distinct, bad, worst))
    if mx >= 0 and bad > mx:
        print("tmflick: FAIL (flicker %d > %d)" % (bad, mx))
        return 1
    print("tmflick: OK")
    return 0


sys.exit(main())
