#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

import numpy as np

slow, off = sys.argv[1:3]
ok = bad = 0
RECT_RE = re.compile(r"settings: rect name=whq x=\d+ y=\d+ w=(\d+) h=(\d+) ax=(\d+) ay=(\d+)")
FRAMES = ["01-frame", "02-frame", "03-frame", "04-frame", "05-frame", "06-frame"]
MIN_DISTINCT_FRAMES = 2
PIXEL_STEP = 60
MIN_SWITCH_W = 24
EDGE_COLUMNS = 2
SWITCH_ROOM = 56
BAR_FILL_PERCENT = 60


def chk(cond, msg):
    global ok, bad
    print(("  OK    " if cond else "  FAIL  ") + msg)
    if cond:
        ok += 1
    else:
        bad += 1


def image(out, name):
    path = os.path.join(out, name + ".ppm")
    if not os.path.exists(path):
        return None
    data = open(path, "rb").read()
    m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+(\d+)\s", data)
    if not m:
        return None
    w, h = int(m[1]), int(m[2])
    return np.frombuffer(data[m.end():], dtype=np.uint8)[: w * h * 3].reshape(h, w, 3).astype(np.int16)


def rect(out):
    found = None
    for ln in open(os.path.join(out, "serial.txt"), "rb").read().decode("latin1").splitlines():
        m = RECT_RE.search(ln)
        if m:
            w, h, ax, ay = (int(v) for v in m.groups())
            found = (ax, ay, w, h)
    return found


def crop(img, r):
    x, y, w, h = r
    return img[y:y + h, x:x + w]


def diff_mask(a, b):
    return np.abs(a - b).sum(axis=2) > PIXEL_STEP


def ink_mask(c):
    bg = np.median(c.reshape(-1, 3), axis=0)
    return np.abs(c - bg).sum(axis=2) > PIXEL_STEP


def distinct(frames):
    out = []
    for f in frames:
        if not out or diff_mask(out[-1], f).any():
            out.append(f)
    return out


def load(out):
    r = rect(out)
    chk(r is not None, "%s: toggle rect reported" % os.path.basename(out))
    imgs = {n: image(out, n) for n in ["00-before", "09-after"] + FRAMES}
    chk(all(v is not None for v in imgs.values()), "%s: all pictures present" % os.path.basename(out))
    if r is None or any(v is None for v in imgs.values()):
        return None, None
    return r, {n: crop(v, r) for n, v in imgs.items()}


SIDEBAR = (0, 60, 260, 660)
SIDEBAR_MAX_CHANGED_PERCENT = 1.0


def sidebar_stable(out):
    a, b = image(out, "00-before"), image(out, "09-after")
    if a is None or b is None:
        return False
    return 100 * diff_mask(crop(a, SIDEBAR), crop(b, SIDEBAR)).mean() <= SIDEBAR_MAX_CHANGED_PERCENT


r, c = load(slow)
chk(sidebar_stable(slow), "slow: theme look unchanged by the switch (sidebar stable)")
if c:
    chk(r[2] >= MIN_SWITCH_W and r[3] >= MIN_SWITCH_W // 2, "toggle rect size %dx%d" % (r[2], r[3]))
    chk(diff_mask(c["00-before"], c["09-after"]).any(), "state flips visibly")
    seq = [c["00-before"]] + [c[n] for n in FRAMES] + [c["09-after"]]
    steps = len(distinct(seq)) - 1
    chk(steps >= MIN_DISTINCT_FRAMES, "slow run shows %d distinct frames (>= %d)" % (steps, MIN_DISTINCT_FRAMES))
    for n in ["00-before", "09-after"]:
        ink = ink_mask(c[n])
        fill = 100 * ink.mean()
        chk(fill < BAR_FILL_PERCENT, "%s: no selection bar (ink %.0f%% < %d%%)" % (n, fill, BAR_FILL_PERCENT))
        label = ink[:, : r[2] - SWITCH_ROOM]
        chk(label.any() and not label[:, -EDGE_COLUMNS:].any(), "%s: label complete (ink present, not cut at switch)" % n)
        chk(ink[:, r[2] - SWITCH_ROOM:].any(), "%s: switch drawn at the right" % n)
    ink_a = ink_mask(c["00-before"])
    ink_b = ink_mask(c["09-after"])
    cols_a = np.where(ink_a.any(axis=0))[0]
    cols_b = np.where(ink_b.any(axis=0))[0]
    chk(len(cols_a) > 0 and len(cols_b) > 0 and abs(int(cols_a.max()) - int(cols_b.max())) <= 1,
        "label extent equal before/after (right edge %s / %s)" % (cols_a.max() if len(cols_a) else "-", cols_b.max() if len(cols_b) else "-"))

r0, c0 = load(off)
if c0:
    chk(diff_mask(c0["00-before"], c0["09-after"]).any(), "motion=0: state flips")
    seq = [c0["00-before"]] + [c0[n] for n in FRAMES] + [c0["09-after"]]
    steps = len(distinct(seq)) - 1
    chk(steps <= 1, "motion=0: jump without intermediate frames (%d steps <= 1)" % steps)

print("TOGGLE: %d ok, %d fail" % (ok, bad))
sys.exit(1 if bad else 0)
