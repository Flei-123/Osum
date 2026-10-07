#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/midline/measure.py -- r402 D-009: ONE CENTRE LINE per row.

    measure.py <picture> <x0> <y0> <x1> <y1> <icon_x0> <icon_x1> <text_x0> <text_x1> <row_h> <first_row_top>

Scans the rows of a list (every row `row_h` high from `first_row_top`) in the picture and prints, per row,
the vertical centre of the ICON ink (columns icon_x0..icon_x1), the centre of the TEXT's x-height band (the
rows whose ink count is at least 55 % of the text's densest row: the body of the lower-case letters, not the
ascenders), and the centre of the ROW.  `OK` when icon and text centres are within 1 px of the row centre
(the `+` / `-` is the offset).
"""
import sys
from PIL import Image


def ink(im, x, y, bg, thr=90):
    p = im.getpixel((x, y))[:3]
    return sum(abs(a - b) for a, b in zip(p, bg)) > thr


def rows(im, top, h, n, ix0, ix1, tx0, tx1, bg):
    out = []
    for r in range(n):
        y0 = top + r * h
        iy = [y for y in range(y0, y0 + h) if any(ink(im, x, y, bg) for x in range(ix0, ix1))]
        cnt = {y: sum(1 for x in range(tx0, tx1) if ink(im, x, y, bg, 140)) for y in range(y0, y0 + h)}
        mx = max(cnt.values()) if cnt else 0
        band = [y for y, c in cnt.items() if mx and c >= 0.55 * mx]
        if not iy or not band:
            out.append(None)
            continue
        out.append(((min(iy) + max(iy)) / 2.0 - y0, (min(band) + max(band)) / 2.0 - y0, (h - 1) / 2.0,
                    (min(iy), max(iy)), (min(band), max(band))))
    return out


def ink_box(im, x0, y0, x1, y1, bg, thr=90):
    """The bounding box (minx, maxx, miny, maxy) of the ink in the rectangle, or None."""
    xs, ys = [], []
    for y in range(y0, y1):
        for x in range(x0, x1):
            if ink(im, x, y, bg, thr):
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return (min(xs), max(xs), min(ys), max(ys))


def band_center(im, x0, x1, y0, y1, bg):
    """The vertical centre of the text's x-height band (rows with at least 55 % of the densest row's ink) in
    the rectangle, or None when there is no text."""
    cnt = {y: sum(1 for x in range(x0, x1) if ink(im, x, y, bg, 140)) for y in range(y0, y1)}
    mx = max(cnt.values()) if cnt else 0
    band = [y for y, c in cnt.items() if mx and c >= 0.55 * mx]
    if not band:
        return None
    return (min(band) + max(band)) / 2.0, (min(band), max(band))


if __name__ == "__main__":
    f = sys.argv[1]
    a = [int(v) for v in sys.argv[2:]]
    im = Image.open(f).convert("RGB")
    x0, y0, x1, y1, ix0, ix1, tx0, tx1, h, top = a
    n = (y1 - y0) // h
    bg = im.getpixel((x0 + 3, top + 2))[:3]
    bad = 0
    for i, r in enumerate(rows(im, top, h, n, ix0, ix1, tx0, tx1, bg)):
        if r is None:
            continue
        ic, tc, rc, ib, tb = r
        okk = abs(ic - rc) <= 1.0 and abs(tc - rc) <= 1.0
        bad += 0 if okk else 1
        print("row %d icon %+.1f text %+.1f (row centre %.1f)  icon ink %s text band %s  %s"
              % (i, ic - rc, tc - rc, rc, ib, tb, "OK" if okk else "OFF"))
    print("midline: %d rows off" % bad)
