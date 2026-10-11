#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/lockflicker/series.py <run dir> <base> <prefix> <px> <py>

Burst series (drive.py `serie click N c`): every frame <prefix>-NNN.ppm is compared with the picture <base> taken BEFORE the click.
Pixels inside a box of 48 px around the pointer (px, py) are ignored (the pointer arrow moves there). Prints per frame the number of
differing pixels (channel difference > 8) and a summary line `SERIES frames=N differing=K max=M`.
Exit 0 = every frame equals the base (no flicker measured), 1 = at least one frame differs, 2 = no frames.
"""
import glob, os, re, sys

def read_ppm(path):
    d = open(path, "rb").read()
    m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+255\s", d)
    return int(m.group(1)), int(m.group(2)), d[m.end():]

def main():
    run, base, pre, px, py = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
    import numpy as np
    w, h, b = read_ppm(os.path.join(run, base + ".ppm"))
    B = np.frombuffer(b, dtype=np.uint8).reshape(h, w, 3).astype(np.int16)
    files = sorted(glob.glob(os.path.join(run, pre + "-[0-9][0-9][0-9].ppm")))
    if not files:
        print("SERIES frames=0")
        return 2
    differing, mx = 0, 0
    for f in files:
        w2, h2, d = read_ppm(f)
        if (w2, h2) != (w, h):
            print("%s size %dx%d" % (os.path.basename(f), w2, h2))
            differing += 1
            continue
        I = np.frombuffer(d, dtype=np.uint8).reshape(h, w, 3).astype(np.int16)
        m = np.abs(I - B).max(axis=2) > 8
        m[max(0, py - 48):py + 48, max(0, px - 48):px + 48] = False
        n = int(m.sum())
        if n:
            ys, xs = np.nonzero(m)
            print("%s differs: %d px, box x %d..%d y %d..%d" % (os.path.basename(f), n, xs.min(), xs.max(), ys.min(), ys.max()))
            differing += 1
            mx = max(mx, n)
    print("SERIES frames=%d differing=%d max=%d" % (len(files), differing, mx))
    return 1 if differing else 0

sys.exit(main())
