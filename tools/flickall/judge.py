#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import glob
import re
import sys

import numpy as np

ROW_TOL = 2
HALF_ROWS = 3
PIX_TOL = 24


def load(p):
    with open(p, "rb") as f:
        d = f.read()
    parts = d.split(b"\n", 3)
    w, h = (int(v) for v in parts[1].split())
    return np.frombuffer(parts[3], dtype=np.uint8).reshape(h, w, 3).astype(np.int16)


def osk_box(serial):
    xs, ys, xe, ye = [], [], [], []
    for m in re.finditer(r"osk: rect name=\S+ x=\d+ y=\d+ w=(\d+) h=(\d+) ax=(\d+) ay=(\d+)", serial):
        w, h, ax, ay = (int(v) for v in m.groups())
        xs.append(ax)
        ys.append(ay)
        xe.append(ax + w)
        ye.append(ay + h)
    if not xs:
        return None
    return min(xs), min(ys), max(xe), max(ye)


def bad_rows(img, ref):
    diff = (np.abs(img - ref).max(axis=2) > PIX_TOL).sum(axis=1)
    return diff > ROW_TOL


def windows(serial):
    rows = re.findall(r"fuiapp: canvas w=(\d+) h=(\d+) atomic=(\d) plain=(\d)", serial)
    return [(int(w), int(h), int(a), int(p)) for w, h, a, p in rows]


def main():
    d = sys.argv[1]
    serial = open(d + "/serial.txt", "rb").read().decode("latin1")
    wins = windows(serial)
    atomic = sum(1 for w in wins if w[2] == 1)
    plain = sum(1 for w in wins if w[3] == 1)
    print("flickall windows: total=%d atomic=%d plain=%d" % (len(wins), atomic, plain))
    box = osk_box(serial)
    if box is None:
        print("flickall osk: no geometry")
        return 1
    x0, y0, x1, y1 = box
    try:
        ra = load(d + "/refa.ppm")[y0:y1, x0:x1]
        rb = load(d + "/refb.ppm")[y0:y1, x0:x1]
    except OSError:
        print("flickall osk: no reference frames")
        return 1
    states = int((np.abs(ra - rb).max(axis=2) > PIX_TOL).any(axis=1).sum())
    frames = sorted(glob.glob(d + "/sw-*.ppm"))
    half = tear = 0
    worst = 0
    for f in frames:
        im = load(f)[y0:y1, x0:x1]
        neither = int((bad_rows(im, ra) & bad_rows(im, rb)).sum())
        worst = max(worst, neither)
        if neither >= HALF_ROWS:
            half += 1
        elif neither > 0:
            tear += 1
    print("flickall osk: box=%d,%d-%d,%d state_rows=%d frames=%d half=%d tear=%d worst_rows=%d"
          % (x0, y0, x1, y1, states, len(frames), half, tear, worst))
    return 0


sys.exit(main())
