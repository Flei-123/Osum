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
    if re.search(r"explorer: strip h=\d+", t):
        oy = gy + fr     # r454: the drawing area starts at the top of the title bar (the tabs live there)
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
    # ---- the icon buttons of the address row (ids 4..7) and of the command bar (30..37): ink centre = button centre
    for rid in (4, 5, 6, 7, 30, 31, 32, 33, 34, 35, 36, 37):
        if rid not in rects:
            continue
        bx, by, bw, bh = rects[rid]
        X, Y = ox + bx, oy + by
        bgp = im.getpixel((X + 1, Y + 1))[:3]
        ys = [yy for yy in range(Y, Y + bh)
              if any(sum(abs(a - b) for a, b in zip(im.getpixel((xx, yy))[:3], bgp)) > 150
                     for xx in range(X + 6, X + bw - 6))]
        if ys:
            off = (min(ys) + max(ys)) / 2.0 - (Y + (bh - 1) / 2.0)
            check(abs(off) <= 1.0, "icon button %d: icon %+.1f from the middle" % (rid, off))
    # ---- the title bar: the title text and the three control glyphs on the centre line of the bar
    wm = re.findall(r"wm: fen i=\d+ id=\d+ x=%d y=%d w=(\d+) h=\d+ [^\n]*? bar=(\d+) capw=\d+ fr=(\d+)" % (gx, gy), t)
    if wm:
        ww, tbar, tfr = (int(v) for v in wm[-1])
        cy_bar = gy + tfr + (tbar - 1) / 2.0
        tbg = im.getpixel((gx + tfr + 3, int(cy_bar)))[:3]
        # the title is judged like tools/fourbugs does (Justin's complaint of 04.10.2026): the gap above the ascender top and
        # the gap below the BASELINE agree within a pixel (descenders hang below the baseline and are not counted: a
        # title of "File Explorer" has a `p`, a title of "Terminal" has none, and both must look centred)
        rows = []
        for yy in range(gy + tfr, gy + tfr + tbar):
            n = 0
            for xx in range(gx + tfr + 8, gx + tfr + 140):
                px = im.getpixel((xx, yy))[:3]
                if sum(abs(a - b) for a, b in zip(px, tbg)) > 150:
                    n += 1
            rows.append(n)
        # r454: with the tabs in the title bar there is no server title text here (the tab labels are measured below)
        if rows and max(rows) > 0 and oy == gy + fr + bar + 1:
            inked = [i for i, n in enumerate(rows) if n > 0]
            solid = [i for i, n in enumerate(rows) if n * 100 >= max(rows) * 35]
            top = inked[0]
            bot = tbar - 1 - solid[-1]
            check(abs(top - bot) <= 1, "title bar: the gap above the title is %d px, below its baseline %d px" % (top, bot))
        for nm, k in (("minimise", 3), ("maximise", 2), ("close", 1)):
            x1 = gx + ww - tfr - 46 * (k - 1)
            box = M.ink_box(im, x1 - 46 + 8, gy + tfr, x1 - 8, gy + tfr + tbar, tbg, 150)
            if box:
                off = (box[2] + box[3]) / 2.0 - cy_bar
                check(abs(off) <= 1.0, "title bar: the %s glyph is %+.1f from the middle of the bar" % (nm, off))
    # ---- the tabs (picture 02-tabs): the label of each tab on the centre line of its box
    p2 = os.path.join(out, "02-tabs.ppm")
    if os.path.exists(p2):
        t2 = Image.open(p2).convert("RGB")
        for rid in (50, 51):
            if rid in rects:
                bx, by, bw, bh = rects[rid]
                X, Y = ox + bx, oy + by
                tb = t2.getpixel((X + 3, Y + bh // 2))[:3]
                r = M.band_center(t2, X + 12, X + min(bw - 30, 80), Y + 3, Y + bh - 3, tb)
                if r:
                    check(abs(r[0] - (Y + (bh - 1) / 2.0)) <= 1.0, "tab %d: the label is %+.1f from the middle of the tab" % (rid - 49, r[0] - (Y + (bh - 1) / 2.0)))
    # ---- the context menu (picture 03-menu): the text of each row on its centre line
    p3 = os.path.join(out, "03-menu.ppm")
    mr = re.findall(r"explorer: menurect wx=(\d+) wy=(\d+) wh=(\d+) zh=(\d+)", t)
    if os.path.exists(p3) and mr:
        t3 = Image.open(p3).convert("RGB")
        mx, my, mh, mzh = (int(v) for v in mr[-1])
        mbg = t3.getpixel((mx + 40, my + mh - 6))[:3]
        rows_n = (mh - 8) // mzh
        done = 0
        for rI in range(min(rows_n, 8)):
            y0 = my + 4 + rI * mzh
            r = M.band_center(t3, mx + 14, mx + 90, y0 + 2, y0 + mzh - 2, mbg)
            if r:
                done += 1
                check(abs(r[0] - (y0 + (mzh - 1) / 2.0)) <= 1.0, "menu row %d: the text is %+.1f from the middle of the row" % (rI, r[0] - (y0 + (mzh - 1) / 2.0)))
        check(done >= 4, "%d menu rows measured" % done)
    # ---- the task bar: the pinned icons and the start button on the centre line of the bar
    gm = re.findall(r"taskbar: geom edge=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", t)
    if gm:
        bx0, by0, bw0, bh0 = (int(v) for v in gm[-1])
        cy_t = by0 + (bh0 - 1) / 2.0
        bgt = im.getpixel((bx0 + bw0 // 2, by0 + bh0 // 2))[:3]
        pins = re.findall(r"taskbar: pin (\w+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", t)
        seen = set()
        for nm, px_, py_, pw_, ph_ in pins:
            if nm in seen:
                continue
            seen.add(nm)
            px_, py_, pw_, ph_ = int(px_), int(py_), int(pw_), int(ph_)
            box = M.ink_box(im, bx0 + px_ + 4, by0 + py_ + 2, bx0 + px_ + pw_ - 4, by0 + py_ + ph_ - 6, bgt, 120)
            if box:
                off = (box[2] + box[3]) / 2.0 - (by0 + py_ + (ph_ - 7) / 2.0 - 0.5)
                check(abs((box[2] + box[3]) / 2.0 - cy_t) <= 2.0, "task bar: the icon of %s is %+.1f from the middle of the bar" % (nm, (box[2] + box[3]) / 2.0 - cy_t))
        ts = re.findall(r"taskbar: start x=(\d+) y=(\d+) w=(\d+) h=(\d+)", t)
        if ts:
            sx_, sy_, sw_, sh_ = (int(v) for v in ts[-1])
            box = M.ink_box(im, bx0 + sx_ + 4, by0 + sy_ + 2, bx0 + sx_ + sw_ - 4, by0 + sy_ + sh_ - 2, bgt, 120)
            if box:
                off = (box[2] + box[3]) / 2.0 - cy_t
                check(abs(off) <= 1.5, "task bar: the start icon is %+.1f from the middle of the bar" % off)


if __name__ == "__main__":
    main(sys.argv[1])
    print("MIDLINE: %d passed, %d failed" % (PASS, FAIL))
    sys.exit(1 if FAIL else 0)
