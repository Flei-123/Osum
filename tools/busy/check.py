import re
import sys

import numpy as np
from PIL import Image

out, serial = sys.argv[1], sys.argv[2]
log = open(serial, errors="replace").read()
fails = []


def ok(cond, text):
    print(("OK   " if cond else "FAIL ") + text)
    if not cond:
        fails.append(text)


def load(name):
    return np.asarray(Image.open("%s/%s.ppm" % (out, name)).convert("RGB")).astype(int)


def diff_box(a, b):
    x0, x1 = 64, 60 + 640 * sc - 4
    y0, y1 = 500, 420 + 420 * sc - 4
    m = np.abs(a - b).sum(axis=2) > 24
    sub = np.zeros_like(m)
    sub[y0:y1, x0:x1] = m[y0:y1, x0:x1]
    ys, xs = np.nonzero(sub)
    if len(xs) == 0:
        return None
    return xs.min(), ys.min(), xs.max(), ys.max()


g = re.search(r"busydemo: geom w=(\d+) h=(\d+) s=(\d+)", log)
ok(g is not None, "geometry line present")
dw, dh, sc = (int(x) for x in g.groups()) if g else (320, 116, 1)
track = dw - 32 * sc

sa, sb, scc = load("spin-a"), load("spin-b"), load("spin-c")
b1, b2 = diff_box(sa, sb), diff_box(sb, scc)
ok(b1 is not None or b2 is not None, "spinner animates between frames")
for bx in (b1, b2):
    if bx:
        ok(bx[2] - bx[0] <= 30 * sc and bx[3] - bx[1] <= 30 * sc, "spinner change confined to %dx%d" % (bx[2] - bx[0] + 1, bx[3] - bx[1] + 1))

def fill_width(img):
    x0, x1 = 64, 60 + 640 * sc - 4
    y0, y1 = 500, 420 + 420 * sc - 4
    r, g, b = img[:, :, 0], img[:, :, 1], img[:, :, 2]
    blue = ((b - r) > 80) & (b > 150)
    sub = np.zeros_like(blue)
    sub[y0:y1, x0:x1] = blue[y0:y1, x0:x1]
    rows = sub.sum(axis=1)
    y = int(rows.argmax())
    if rows[y] < 8 * sc:
        return 0
    xs = np.nonzero(sub[y])[0]
    return int(xs.max() - xs.min() + 1)


for name, pct in (("pct-000", 0), ("pct-030", 30), ("pct-070", 70), ("pct-100", 100)):
    w = fill_width(load(name))
    want = track * pct / 100
    good = w <= 20 * sc if pct == 0 else abs(w - want) <= 4 * sc + 2
    ok(good, "%s: fill %d px, expected %.0f" % (name, w, want))

ia, ib = load("indet-a"), load("indet-b")
bx = diff_box(ia, ib)
ok(bx is not None, "indeterminate bar moves")
cb = load("cancel-btn")
ok(diff_box(cb, ia) is not None, "cancel dialog differs from plain busy dialog")
ok("busydemo: cancelled=1" in log, "cancel button/key ends the wait")
ok(re.search(r"busydemo: run ok r=0 steps=25", log) is not None, "run: worker finished (r=0, 25 steps)")
ok(re.search(r"busydemo: run timeout r=2", log) is not None, "run: timeout reported (r=2)")
ok(re.search(r"busydemo: run cancel r=1", log) is not None, "run: cancel reported (r=1)")
ok("busydemo: alert-closed" in log, "alert closed by Enter")
ok("busydemo: confirm=0" in log, "confirm answered false by Esc")
ok("busydemo: done" in log, "demo finished")
lum = float(load("spin-a")[:, :, :].mean())
print("mean luminance %.1f" % lum)
print("RESULT %d fail" % len(fails))
sys.exit(1 if fails else 0)
