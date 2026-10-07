#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/midline/check.py <audit-outdir> -- D-009: icon, text and row share ONE centre line (<= 1 px).

Reads `explorer: geom`, `explorer: rect id=`, `explorer: rows` and `explorer: navrows` out of serial.txt, the
picture 01-explorer.ppm, and measures (measure.py) the rows of the detail list, of the navigation pane (its
group headings are skipped, a sub-folder row is one level further in) and the four icon buttons of the
command row.  The chrome offset of the window is frame + bar + 1 (read from `wm: fen ... bar= fr=`)."""
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
    zh = re.findall(r"explorer: rows .*? zh=(\d+)", t)
    zh = int(zh[-1]) if zh else 32
    kinds = re.findall(r"explorer: navrows ([hpus]+)", t)
    kinds = kinds[-1] if kinds else ""
    im = Image.open(os.path.join(out, "01-explorer.ppm")).convert("RGB")
    # ---- the detail list (id 26): header 28 + 2, then rows of `zh`
    lx, ly, lw, lh = rects[26]
    X, Y = ox + lx, oy + ly
    top = Y + 28 + 2
    bg = im.getpixel((X + lw - 40, top + zh // 2))[:3]
    res = M.rows(im, top, zh, 6, X + 14, X + 36, X + 46, X + 100, bg)
    nrow = 0
    for i, r in enumerate(res):
        if r is None:
            continue
        nrow += 1
        ic, tc, rc = r[0], r[1], r[2]
        check(abs(ic - rc) <= 1.0 and abs(tc - rc) <= 1.0,
              "detail list row %d: icon %+.1f, text %+.1f from the row centre" % (i, ic - rc, tc - rc))
    check(nrow >= 4, "%d detail rows measured" % nrow)
    # ---- the navigation pane (id 24): one row per char of `navrows`
    if 24 in rects and kinds:
        lx, ly, lw, lh = rects[24]
        X, Y = ox + lx, oy + ly
        bg = im.getpixel((X + lw - 20, Y + 6))[:3]
        measured = 0
        for i, k in enumerate(kinds):
            if k == "h":
                continue
            y0 = Y + 2 + i * zh
            if y0 + zh > Y + lh:
                break
            lvl = 1 if k == "s" else 0
            r = M.rows(im, y0, zh, 1, X + 8 + 16 * lvl, X + 30 + 16 * lvl, X + 40 + 16 * lvl, X + 90 + 16 * lvl, bg)[0]
            if r is None:
                continue
            ic, tc, rc = r[0], r[1], r[2]
            if r[4][1] - r[4][0] < 4:
                continue            # ".." has no body of lower-case letters to measure
            measured += 1
            check(abs(ic - rc) <= 1.0 and abs(tc - rc) <= 1.0,
                  "navigation row %d (%s): icon %+.1f, text %+.1f" % (i, k, ic - rc, tc - rc))
        check(measured >= 5, "%d navigation rows measured" % measured)
    # ---- the icon buttons of the address row (ids 4..7, 36 x 36): ink centre = button centre
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
