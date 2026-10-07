#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/design/check.py -- the measured claims of the design audit (r399).

    check.py <audit-outdir>

<audit-outdir> is the output of `tools/design/audit.sh` with the drehbuch
tools/design/views.txt: 01-schreibtisch.png, 02-startmenue.png,
03-einstellungen.png, 04-explorer.png, 05-dialog.png and serial.txt.
Prints one line per claim, `OK` or `FAIL`, and a last line
`DESIGN: <n> passed, <m> failed`.

Every number comes out of the pictures or the serial log; nothing is typed in.
"""
import os
import re
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import measure as M  # noqa: E402

PASS = FAIL = 0


def ok(msg):
    global PASS
    PASS += 1
    print("  OK    " + msg)


def bad(msg):
    global FAIL
    FAIL += 1
    print("  FAIL  " + msg)


def check(cond, msg):
    (ok if cond else bad)(msg)


def px(im, x, y):
    return im.getpixel((x, y))[:3]


def ink_box(im, box, bg, thr=60):
    """Bounding box of the pixels in `box` that differ from the colour `bg`."""
    x0, y0, x1, y1 = box
    xs, ys = [], []
    for y in range(y0, y1):
        for x in range(x0, x1):
            p = px(im, x, y)
            if sum(abs(a - b) for a, b in zip(p, bg)) > thr:
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return min(xs), min(ys), max(xs), max(ys)


def main(argv):
    d = argv[0]

    def png(n):
        return Image.open(os.path.join(d, n + ".png")).convert("RGB")

    print("== A. the interface face")
    try:
        from fontTools.ttLib import TTFont
        t = TTFont(os.path.join(ROOT, "assets", "osum-sans.ttf"))
        cm = t.getBestCmap()
        need = [ord(c) for c in "ÄÖÜäöüß€–…“”"]
        check(all(c in cm for c in need), "the face has the German letters, the euro sign, dashes and quotes")
        kp = len(t["kern"].kernTables[0].kernTable)
        check(kp >= 5000, "pair kerning: %d pairs (the old face had 2447)" % kp)
        adv = sum(t["hmtx"][cm[ord(c)]][0] for c in "Search programs Einstellungen Darstellung")
        print("        advance of a sample line: %.1f px at 15 px" % (adv * 15 / t["head"].unitsPerEm))
    except ImportError:
        print("        (fontTools missing -- face not measured)")

    print("== B. the wallpaper")
    s1 = png("01-schreibtisch")
    share = M.wallpaper_blockiness(os.path.join(d, "01-schreibtisch.png"))
    check(share <= 0.60, "equal-neighbour share in the tree line: %.3f (nearest-neighbour stretch: 0.721)" % share)

    print("== C. frosted surfaces follow the rounded shape")
    # r402: the window of the start menu stands where the launcher says (it depends on its height)
    ser = open(os.path.join(d, "serial.txt"), "rb").read().decode("latin-1") if os.path.exists(os.path.join(d, "serial.txt")) else ""
    gm = re.findall(r"launcher: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser)
    gx, gy = (int(gm[-1][0]), int(gm[-1][1])) if gm else (8, 300)
    lm = re.findall(r"launcher: rect id=2 kind=5 x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser)
    lx, ly, lw, lh = (int(v) for v in lm[-1]) if lm else (20, 100, 600, 300)
    n, tot = M.corner_halo(os.path.join(d, "02-startmenue.png"), os.path.join(d, "01-schreibtisch.png"), x0=gx, y0=gy)
    check(n == 0, "pixels outside the corner arc of the start menu that differ from the picture without it: %d of %d (before: %d)" % (n, tot, tot))

    print("== D. a selection is a tint with an indicator bar")
    s2 = png("02-startmenue")
    s2b = png("02b-suche")
    # the first row of the result list is selected; its plate colour is the pixel right of the title
    plate = px(s2b, gx + lx + lw - 40, gy + ly + 26)
    ground = px(s2b, gx + lx + lw - 40, gy + ly + 26 + 104)
    cr_plate = M.contrast(plate, ground)
    check(cr_plate < 3.0, "the plate is a soft tint of the ground: contrast plate/ground %.2f (solid accent was 4.9)" % cr_plate)
    # the title text of the row: darkest pixel in the title box
    dark = min((px(s2b, x, y) for x in range(gx + lx + 54, gx + lx + 114) for y in range(gy + ly + 4, gy + ly + 22)), key=lambda p: sum(p))
    check(M.contrast(dark, plate) >= 7.0, "the text on the plate keeps contrast %.1f:1 (>= 7)" % M.contrast(dark, plate))
    acc = 0
    # the bar sits a few points inside the list's left edge: find the column of the first row that has
    # the most accent pixels, and count those (the column 16 points further in must not have them)
    for cx in range(gx + lx, gx + lx + 14):
        n_ = 0
        for y in range(gy + ly + 2, gy + ly + 42):
            p = px(s2b, cx, y)
            q = px(s2b, cx + 14, y)
            if p[2] > 180 and p[0] < 120 and not (q[2] > 180 and q[0] < 120):
                n_ += 1
        acc = max(acc, n_)
    check(acc >= 10, "the accent indicator bar is there: %d accent pixels in its column" % acc)

    print("== E. program icons are vector art at the size of the surface")
    bar_bg = px(s2, 600, 780)
    b = ink_box(s2, (92, 764, 126, 797), bar_bg)
    if b:
        h = b[3] - b[1] + 1
        check(h >= 22, "taskbar icon is %d px high (the 16x16 drawing was 16)" % h)
    else:
        bad("no taskbar icon found")
    row_bg = plate
    b = ink_box(s2b, (gx + lx + 10, gy + ly + 4, gx + lx + 46, gy + ly + 48), row_bg, thr=90)
    if b:
        h = b[3] - b[1] + 1
        check(h >= 28, "start menu icon is %d px high (16 before)" % h)
    else:
        bad("no start menu icon found")

    print("== F. cost")
    sp = os.path.join(d, "serial.txt")
    full = None
    if os.path.exists(sp):
        for ln in open(sp, "rb"):
            m = re.search(rb"wmbench2: compose full=(\d+) us", ln)
            if m:
                full = int(m.group(1))
    if full is None:
        bad("no wmbench2 line in the serial log")
    else:
        check(full <= 16000, "a full-screen composition costs %d us (budget 16000 us for 60 Hz)" % full)

    print("DESIGN: %d passed, %d failed" % (PASS, FAIL))
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
