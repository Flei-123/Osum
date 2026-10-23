#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/tmflick/blank.py <dir> <prefix> [--max N] -- W-FLICKER resize sweep: count frames whose client area is (mostly) flat dark = blank flash.

The task manager client area is light (panel background); a frame where fewer than half of the pixels in the 40..600 x 60..600 box are
light is the window cleared to the dark background colour (or a half-painted picture).
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


def main():
    d, pre = sys.argv[1], sys.argv[2]
    mx = int(sys.argv[sys.argv.index("--max") + 1]) if "--max" in sys.argv else -1
    fr = []
    for f in sorted(glob.glob("%s/%s-*.ppm" % (d, pre))):
        im = load(f)[60:600, 40:600]
        fr.append(float((im.sum(axis=2) > 600).mean()))
    sw = fr[2:]
    blank = sum(1 for v in sw if v < 0.5)
    print("tmflick-resize: frames=%d blank=%d min_light=%.2f" % (len(sw), blank, min(sw)))
    if mx >= 0 and blank > mx:
        print("tmflick-resize: FAIL (blank %d > %d)" % (blank, mx))
        return 1
    print("tmflick-resize: OK")
    return 0


sys.exit(main())
