#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os, re, sys
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "wm"))
import cursor2

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
    name, hot, pts = cursor2.FORMEN[idx]
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
    px = G / g
    for margin in (0.8, 0.5, 0.25):
        core = inside & (dist > margin * px)
        rim = (~inside) & (dist > margin * px) & (dist < 1.33 - margin * px)
        if core.sum() + rim.sum() >= 12:
            break
    return core, rim, int(round(hot[0] * g / G)), int(round(hot[1] * g / G)), inside | (dist < 1.33 + 1.5 * px), inside, dist

def classify(img, hx, hy, g, base=None, slack=3):
    best, bs, scores = -1, -9.0, []
    for idx in range(len(cursor2.FORMEN)):
        core, rim, ox, oy, near, inside, dist = ref(idx, g)
        sc = -9.0
        if base is not None:
            D = np.abs(img - base).sum(axis=2) > 90
            for rw in (0.8, 1.33, 1.9):
                S = np.zeros((g + 8, g + 8), bool)
                S[4:4 + g, 4:4 + g] = inside | (dist < rw)
                for dy in range(-slack, slack + 1):
                    for dx in range(-slack, slack + 1):
                        x0, y0 = hx - ox + dx - 4, hy - oy + dy - 4
                        if x0 < 0 or y0 < 0:
                            continue
                        box = D[y0:y0 + g + 8, x0:x0 + g + 8]
                        if box.shape != S.shape:
                            continue
                        sc = max(sc, (box & S).sum() / max(1, (box | S).sum()))
        else:
            x0, y0 = hx - ox, hy - oy
            box = img[y0 - 4:y0 + g + 4, x0 - 4:x0 + g + 4]
            if box.shape[0] == g + 8 and box.shape[1] == g + 8:
                fp = np.zeros((g + 8, g + 8), bool)
                fp[4:4 + g, 4:4 + g] = near
                sure = np.zeros((g + 8, g + 8), bool)
                sure[4:4 + g, 4:4 + g] = core | rim
                luma = box.sum(axis=2) / 3.0
                sc = (((luma > 215) & sure).sum() + ((luma < 60) & sure).sum()) / max(1, sure.sum()) \
                     - 2.0 * ((luma > 215) & ~fp).sum() / float(g * g)
        scores.append(sc)
        if sc > bs:
            bs, best = sc, idx
    return best, scores

TARGETS = [("01-desktop", "aussen", 0), ("02-terminal", "mitte", 1), ("03-title", "titel", 0),
           ("04-edge-r", "r", 3), ("05-corner-ru", "ru", 5), ("06-edge-b", "u", 4), ("07-corner-lo", "lo", 5)]
txt = open(log, "rb").read().decode("latin1")
spots = [(m.group(1), int(m.group(2)), int(m.group(3))) for m in
         re.finditer(r"fahrekante id=7 (\S+) -> (\d+),(\d+)", txt)]
g = 24 * scale
seen = {}
bases = []
for nm, sp in (("01-desktop", spots[0] if spots else None), ("99-away", spots[-1] if spots else None)):
    f = os.path.join(out, nm + ".ppm")
    if sp and os.path.exists(f):
        bases.append((ppm(f), sp[1], sp[2]))
for (ph, where, want), (w2, x, y) in zip(TARGETS, spots):
    f = os.path.join(out, ph + ".ppm")
    if not os.path.exists(f):
        ok(False, "%s: picture missing" % ph); continue
    img = ppm(f)
    base = None
    if bases and ph != "01-desktop":
        base = max(bases, key=lambda b: abs(b[1] - x) + abs(b[2] - y))
        if abs(base[1] - x) + abs(base[2] - y) < 2 * g:
            base = None
        else:
            base = base[0]
    best, sc = classify(img, x, y, g, base)
    seen[ph] = best
    ok(best == want, "%s at %s (%d,%d): shape %s, expected %s  [score %.2f vs best other %.2f]"
       % (ph, where, x, y, cursor2.NAMES[best] if best >= 0 else "?", cursor2.NAMES[want],
          sc[want], max(v for i, v in enumerate(sc) if i != want)))
ok(len(spots) >= 7, "drive log names %d spots" % len(spots))
ser = open(ser_path, "rb").read().decode("latin1")
forms = [int(m.group(1)) for m in re.finditer(r"wm: form=(\d+) x=", ser)]
ok(bool(forms) and max(forms) < len(cursor2.FORMEN), "serial: %d shape changes, all < %d" % (len(forms), len(cursor2.FORMEN)))
for want in (0, 1, 3, 4, 5):
    ok(want in forms, "serial: shape %s was announced" % cursor2.NAMES[want])
sys.exit(fails)
