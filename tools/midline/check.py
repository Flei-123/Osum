#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/midline/check.py <audit-outdir> -- D-009: icon, text and row share ONE centre line (<= 1 px).

Reads `explorer: geom` and `explorer: rect id=` out of serial.txt, the picture 01-explorer.ppm, and
measures (measure.py) the rows of the detail list and of the two left lists, and the four icon buttons of
the tool bar.  The chrome offset of the window is frame + bar + 1 (read from `wm: fen ... bar= fr=`)."""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import measure as M  # noqa: E402
from PIL import Image  # noqa: E402

PASS = FAIL = 0


def check(c, m):
    global PASS, FAIL
    if c:
        PASS += 1
    else:
        FAIL += 1
    print(("  OK    " if c else "  FAIL  ") + m)


def main(out):
    t = open(os.path.join(out, "serial.txt"), "rb").read().decode("latin-1")
    g = re.findall(r"explorer: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)", t)
    check(bool(g), "the file manager reports its window")
    if not g:
        return
    gx, gy = int(g[-1][0]), int(g[-1][1])
    c = re.findall(r"wm: fen i=\d+ id=\d+ x=%d y=%d [^\n]*? bar=(\d+) capw=\d+ fr=(\d+)" % (gx, gy), t)
    bar, fr = (int(c[-1][0]), int(c[-1][1])) if c else (32, 1)   # (the shape osum; F12 prints the real ones)
    ox, oy = gx + fr, gy + fr + bar + 1
    rects = {}
    for m in re.finditer(r"explorer: rect id=(\d+) kind=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", t):
        rects[int(m.group(1))] = tuple(int(v) for v in m.groups()[1:])
    im = Image.open(os.path.join(out, "01-explorer.ppm")).convert("RGB")
    # ---- the detail list (id 26): header 28 + 2, then rows of 28
    lx, ly, lw, lh = rects[26]
    X, Y = ox + lx, oy + ly
    tops = []
    # the first row top: the selection plate / the first row after the header (x-column near the left)
    top = Y + 28 + 2
    bg = im.getpixel((X + lw - 40, top + 14))[:3]
    res = M.rows(im, top, 28, 6, X + 14, X + 36, X + 46, X + 100, bg)
    nrow = 0
    for i, r in enumerate(res):
        if r is None:
            continue
        nrow += 1
        ic, tc, rc = r[0], r[1], r[2]
        check(abs(ic - rc) <= 1.0 and abs(tc - rc) <= 1.0,
              "detail list row %d: icon %+.1f, text %+.1f from the row centre" % (i, ic - rc, tc - rc))
    check(nrow >= 4, "%d detail rows measured" % nrow)
    # ---- the left lists (ids 24 / 25)
    for rid, nm in ((24, "places"), (25, "folders")):
        if rid not in rects:
            continue
        lx, ly, lw, lh = rects[rid]
        X, Y = ox + lx, oy + ly
        bg = im.getpixel((X + lw - 20, Y + 20))[:3]
        res = M.rows(im, Y + 2, 28, 4, X + 8, X + 30, X + 40, X + 90, bg)
        for i, r in enumerate(res):
            if r is None:
                continue
            ic, tc, rc = r[0], r[1], r[2]
            if r[4][1] - r[4][0] < 4:
                continue            # ".." has no body of lower-case letters to measure
            check(abs(ic - rc) <= 1.0 and abs(tc - rc) <= 1.0,
                  "%s row %d: icon %+.1f, text %+.1f" % (nm, i, ic - rc, tc - rc))
    # ---- the icon buttons of the tool bar (ids 4..8, 36 x 36): ink centre = button centre
    for rid in (4, 5, 6, 7):
        bx, by, bw, bh = rects[rid]
        X, Y = ox + bx, oy + by
        bgp = im.getpixel((X + 1, Y + 1))[:3]
        ys = [yy for yy in range(Y, Y + bh)
              if any(sum(abs(a - b) for a, b in zip(im.getpixel((xx, yy))[:3], bgp)) > 150
                     for xx in range(X + 6, X + bw - 6))]
        if ys:
            off = (min(ys) + max(ys)) / 2.0 - (Y + (bh - 1) / 2.0)
            check(abs(off) <= 1.0, "tool bar button %d: icon %+.1f from the middle" % (rid, off))


if __name__ == "__main__":
    main(sys.argv[1])
    print("MIDLINE: %d passed, %d failed" % (PASS, FAIL))
    sys.exit(1 if FAIL else 0)
