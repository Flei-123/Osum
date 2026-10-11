#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/cursor/check.py <outdir> <log> <serial> <scale> -- W-CURSOR checks.

For every `foto NN-name` of tools/cursor/dreh.txt the picture is cut around the
pointer's hot spot (the spot the drehbuch moved to is in the drive log as
`fahrekante id=7 <where> -> X,Y`) and each of the ten shapes is rendered
here from the SAME outlines the kernel uses (tools/wm/zeiger2.py), at the
target size (24 px * scale). The score of a shape is how many of its sure
rim pixels are white and sure core pixels dark in the picture, minus the
white/dark ink in the box that the shape does not explain. The best shape must
be the expected one. Prints `  OK` / `  FAIL` lines; exit code = number of FAIL.
Also checks the serial `wm: form=` lines against the same expectation."""
import os, re, sys
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "wm"))
import zeiger2

out, log, ser_path = sys.argv[1], sys.argv[2], sys.argv[3]
scale = int(sys.argv[4]) if len(sys.argv) > 4 else 1
fails = 0
def ok(c, m):
    global fails
    print(("  OK    " if c else "  FAIL  ") + m)
    if not c:
        fails += 1

def ppm(path):
    d = open(path, "rb").read()
    m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+(\d+)\s", d)
    w, h = int(m.group(1)), int(m.group(2))
    return np.frombuffer(d[m.end():], dtype=np.uint8)[:w * h * 3].reshape(h, w, 3).astype(int)

G = 24.0
def ref(idx, g):
    """sure core (dark) and sure rim (white) masks of shape idx at g px, plus the hot spot"""
    name, hot, pts = zeiger2.FORMEN[idx]
    P = np.array(pts)
    ys, xs = np.mgrid[0:g, 0:g]
    cx = (xs + 0.5) * G / g
    cy = (ys + 0.5) * G / g
    inside = np.zeros((g, g), bool)
    n = len(P)
    for i in range(n):
        xi, yi = P[i]; xj, yj = P[i - 1]
        if yi == yj:
            continue
        cond = (yi > cy) != (yj > cy)
        xint = (xj - xi) * (cy - yi) / (yj - yi) + xi
        inside ^= cond & (cx < xint)
    dist = np.full((g, g), 99.0)
    for i in range(n):
        a = P[i - 1]; b = P[i]
        ab = b - a
        t = np.clip(((cx - a[0]) * ab[0] + (cy - a[1]) * ab[1]) / (ab @ ab), 0, 1)
        d = np.hypot(cx - (a[0] + t * ab[0]), cy - (a[1] + t * ab[1]))
        dist = np.minimum(dist, d)
    px = G / g                      # design units per pixel
    core = inside & (dist > 0.8 * px)
    rim = (~inside) & (dist > 0.8 * px) & (dist < 1.33 - 0.8 * px)
    return core, rim, int(round(hot[0] * g / G)), int(round(hot[1] * g / G)), inside | (dist < 1.33 + 1.5 * px)

def classify(img, hx, hy, g, base=None):
    """base = the same picture with the pointer elsewhere: the difference is the pointer alone (the
    terminal grid and the diagnostic board carry text that would otherwise look like ink)"""
    best, bs, scores = -1, -9.0, []
    for idx in range(len(zeiger2.FORMEN)):
        core, rim, ox, oy, near = ref(idx, g)
        x0, y0 = hx - ox, hy - oy
        box = img[y0 - 4:y0 + g + 4, x0 - 4:x0 + g + 4]
        if box.shape[0] != g + 8 or box.shape[1] != g + 8:
            scores.append(-9); continue
        fp = np.zeros((g + 8, g + 8), bool)
        fp[4:4 + g, 4:4 + g] = near
        sure = np.zeros((g + 8, g + 8), bool)
        sure[4:4 + g, 4:4 + g] = core | rim
        if base is not None:
            bb = base[y0 - 4:y0 + g + 4, x0 - 4:x0 + g + 4]
            D = np.abs(box - bb).sum(axis=2) > 90
            prec = (D & fp).sum() / max(1, D.sum())
            rec = (D & sure).sum() / max(1, sure.sum())
            sc = prec * rec
        else:
            luma = box.sum(axis=2) / 3.0
            sc = (((luma > 215) & sure).sum() + ((luma < 60) & sure).sum()) / max(1, sure.sum()) \
                 - 2.0 * ((luma > 215) & ~fp).sum() / float(g * g)
        scores.append(sc)
        if sc > bs:
            bs, best = sc, idx
    return best, scores

# targets: (photo, where, expected shape)
TARGETS = [("01-desktop", "aussen", 0), ("02-terminal", "mitte", 1), ("03-title", "titel", 0),
           ("04-edge-r", "r", 3), ("05-corner-ru", "ru", 5), ("06-edge-b", "u", 4), ("07-corner-lo", "lo", 5)]
txt = open(log, "rb").read().decode("latin1")
spots = [(m.group(1), int(m.group(2)), int(m.group(3))) for m in
         re.finditer(r"fahrekante id=7 (\S+) -> (\d+),(\d+)", txt)]
g = 24 * scale
seen = {}
names = [z[1] for z in TARGETS]
# the first seven spots of the drehbuch belong to the seven photos
for (ph, where, want), (w2, x, y) in zip(TARGETS, spots):
    f = os.path.join(out, ph + ".ppm")
    if not os.path.exists(f):
        ok(False, "%s: picture missing" % ph); continue
    img = ppm(f)
    fb = os.path.join(out, "99-away.ppm")
    best, sc = classify(img, x, y, g, ppm(fb) if want != 0 or ph != "01-desktop" else None)
    seen[ph] = best
    ok(best == want, "%s at %s (%d,%d): shape %s, expected %s  [score %.2f vs best other %.2f]"
       % (ph, where, x, y, zeiger2.NAMEN[best] if best >= 0 else "?", zeiger2.NAMEN[want],
          sc[want], max(v for i, v in enumerate(sc) if i != want)))
ok(len(spots) >= 7, "drive log names %d spots" % len(spots))
# serial: every form line names a legal shape; resize/text/arrow all occurred
ser = open(ser_path, "rb").read().decode("latin1")
forms = [int(m.group(1)) for m in re.finditer(r"wm: form=(\d+) x=", ser)]
ok(bool(forms) and max(forms) < len(zeiger2.FORMEN), "serial: %d shape changes, all < %d" % (len(forms), len(zeiger2.FORMEN)))
for want in (0, 1, 3, 4, 5):
    ok(want in forms, "serial: shape %s was announced" % zeiger2.NAMEN[want])
sys.exit(fails)
