#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/startmenu/check.py -- the measured claims of the Windows 11 start menu (r402).

    check.py <audit-outdir>

<audit-outdir> is the output of `tools/design/audit.sh` with tools/startmenu/menu.txt:
01-home .. 10-energie (.png) and serial.txt.  One line per claim, `OK` or `FAIL`, and a last
line `STARTMENU: <n> passed, <m> failed`.  The numbers come out of the pictures and the
launcher's own report (`launcher: geom / rect / tile / rec / w11`); the typed ones are the
claims (640 wide, 600 field, 100 x 88 tiles, six columns, 8 above the bar).
"""
import os
import re
import sys

from PIL import Image

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


def lum(p):
    return (299 * p[0] + 587 * p[1] + 114 * p[2]) // 1000


def img(out, name):
    return Image.open(os.path.join(out, name + ".png")).convert("RGB")


def main(out):
    t = open(os.path.join(out, "serial.txt"), "rb").read().decode("latin-1")
    g = re.findall(r"launcher: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)", t)
    check(bool(g), "the launcher reports its window")
    if not g:
        return
    gx, gy, gw, gh = (int(v) for v in g[-1])
    bar = 40
    mb = re.findall(r"taskbar: geom edge=\d+ x=\d+ y=(\d+) w=\d+ h=(\d+)", t)
    top_bar = int(mb[-1][0]) if mb else 760
    check(gw == 640, "the window is 640 wide (%d)" % gw)
    check(gy + gh == top_bar - 8, "it stands 8 above the bar (bottom %d, bar top %d)"
          % (gy + gh, top_bar))
    # ---- the field and the tiles, from the report
    f = re.findall(r"launcher: rect id=1 kind=4 x=(\d+) y=(\d+) w=(\d+) h=(\d+)", t)
    check(bool(f), "the search field is reported")
    if f:
        fx, fy, fw, fh = (int(v) for v in f[-1])
        check(fw == 600 and fh == 40 and fx == 20,
              "the search field is 600 x 40 at the padding (x=%d w=%d h=%d)" % (fx, fw, fh))
    tiles = re.findall(r"launcher: tile i=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)\s+name=\[([^\]]*)\]", t)
    first = {}
    # the serial line is shared with other programs (`say` is not atomic): a torn line carries a name
    # with garbage behind it. The real names are the ones the launcher reports as programmes
    # (`launcher: treffer i= name=[X] exec=[..]`).
    valid = set(re.findall(r"launcher: treffer i=\d+ name=\[([^\]]*)\] exec=", t))
    for k, x, y, w, h, name in tiles:
        if int(k) < 130 and name in valid and name not in first:
            first[name] = (int(x), int(y), int(w), int(h))
    check(len(first) >= 3, "the pinned tiles are reported (%d)" % len(first))
    check(all(w == 100 and h == 88 for (_, _, w, h) in first.values()),
          "every pinned tile is 100 x 88")
    xs = sorted({x for (x, _, _, _) in first.values()})
    check(all((x - 20) % 100 == 0 for x in xs), "the tiles stand in a grid of 100 (columns at %s)" % xs)
    m = re.findall(r"launcher: w11 home=(\d) +pin=(\d+) +rec=(\d+)", t)
    check(bool(m) and m[0][0] == "1", "the first picture is the home view (home=1)")
    npin = int(m[0][1]) if m else 0
    check(npin == len(first), "the report counts %d pinned tiles and names %d" % (npin, len(first)))
    # ---- pictures
    im1 = img(out, "01-home")
    bgp = px(im1, gx + 12, gy + gh // 2)
    st = first.get("Settings")
    check(st is not None, "the Settings tile is there")
    if st:
        # the icon: coloured pixels in the upper part of the tile, the label under it, centred
        icon = sum(1 for yy in range(gy + st[1] + 10, gy + st[1] + 46)
                   for xx in range(gx + st[0] + 30, gx + st[0] + 70)
                   if sum(abs(a - b) for a, b in zip(px(im1, xx, yy), bgp)) > 60)
        check(icon > 300, "the tile carries a 32 point icon (%d ink pixels)" % icon)
        xsum = n = 0
        for yy in range(gy + st[1] + 56, gy + st[1] + 82):
            for xx in range(gx + st[0], gx + st[0] + st[2]):
                if sum(abs(a - b) for a, b in zip(px(im1, xx, yy), bgp)) > 150:
                    xsum += xx
                    n += 1
        if n:
            cx = xsum / n - (gx + st[0])
            check(abs(cx - st[2] / 2) <= 8, "the label is centred under the icon (centre %.1f of %d)"
                  % (cx, st[2]))
        else:
            bad("no label ink under the icon")
        # ---- hover: a soft plate the size of the tile, the neighbour has none
        im2 = img(out, "02-hover")
        c0 = lum(px(im1, gx + st[0] + 6, gy + st[1] + 6))
        c1 = lum(px(im2, gx + st[0] + 6, gy + st[1] + 6))
        check(abs(c1 - c0) >= 4, "hover paints a plate on the tile (%d against %d)" % (c0, c1))
        run = 0
        best = 0
        for xx in range(gx + st[0] - 20, gx + st[0] + st[2] + 20):
            if abs(lum(px(im2, xx, gy + st[1] + 6)) - c0) >= 4:
                run += 1
                best = max(best, run)
            else:
                run = 0
        check(abs(best - st[2]) <= 4, "the plate is %d wide (tile %d)" % (best, st[2]))
        # nothing else in the window changes under the pointer (the menu is blurred acrylic: a
        # dirty strip that did not grow to the whole window would smear -- tools/menuhover's bug)
        bad = 0
        tx0, ty0 = gx + st[0], gy + st[1]
        for yy in range(gy, gy + gh):
            for xx in range(gx, gx + gw):
                if tx0 - 2 <= xx < tx0 + st[2] + 2 and ty0 - 2 <= yy < ty0 + st[3] + 2:
                    continue
                if xx < gx + 60 and yy >= gy + gh - 40:
                    continue            # the tooltip of the Start button (the pointer left it) reaches in here
                if max(abs(a - b) for a, b in zip(px(im1, xx, yy), px(im2, xx, yy))) > 12:
                    bad += 1
        check(bad <= 5, "hover changes nothing in the window outside the tile (%d points)" % bad)
        nb = first.get("Search")
        if nb:
            check(abs(lum(px(im2, gx + nb[0] + 6, gy + nb[1] + 6)) - c0) < 4,
                  "and the neighbour tile has none")
    # ---- search
    check(re.search(r"launcher: suche \[set\] treffer=[1-9]", t) is not None,
          "typing 'set' filters (report `launcher: suche [set]`)")
    s4 = img(out, "04-suche")
    check(sum(1 for yy in range(gy + 70, gy + 110) for xx in range(gx + 30, gx + 200)
              if lum(px(s4, xx, yy)) < 90) > 30, "the picture shows the result header")
    # ---- again, All apps, back
    homes = re.findall(r"launcher: w11 home=(\d)", t)
    check(len(homes) >= 2 and homes[1] == "1", "reopened: the home view again (%s)" % homes[:3])
    check(len(re.findall(r"launcher: suche \[\] treffer=\d+", t)) >= 2,
          "All apps shows the whole list (a `suche []` report after the click)")
    a5 = img(out, "05-wieder")
    a7 = img(out, "07-zurueck")
    same = tot = 0
    for yy in range(gy + 110, gy + gh - 70, 3):      # below the header row: the pointer stands up there
        for xx in range(gx + 20, gx + gw - 20, 3):
            tot += 1
            if sum(abs(a - b) for a, b in zip(px(a5, xx, yy), px(a7, xx, yy))) < 24:
                same += 1
    check(same * 100 >= 97 * tot, "Back is the home view again (%d of %d samples equal)" % (same, tot))
    # ---- start, remember, power
    check("launcher: start /apps/settings.osp/start" in t, "a tile click starts the programme")
    check(re.search(r"launcher: rec k=0 name=\[Settings\]", t) is not None,
          "the next opening lists it under Recommended (the recent one first)")
    check("launcher: energie auf" in t, "the power button opens its menu")


if __name__ == "__main__":
    main(sys.argv[1])
    print("STARTMENU: %d passed, %d failed" % (PASS, FAIL))
    sys.exit(1 if FAIL else 0)
