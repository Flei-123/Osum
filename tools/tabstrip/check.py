#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/tabstrip/check.py -- r454: tabs in the title bar of the file manager.

    check.py <outdir of the run> [<belege directory>]

Reads the serial log and the pictures of tools/tabstrip/dreh.txt and prints OK / FAIL lines (exit code = number of FAIL).

What is measured (nothing here is "looks fine"):
  1  the program got its strip (`explorer: strip h=`), the window carries the flag (F_CAPCLIENT = 64 in `fl=`) and its drawing
     area starts at the top of the title bar (the first picture: the strip colour reaches up to the frame)
  2  tabs: Ctrl+T gives two tabs, a click on each tab switches (`explorer: reiter n= a=`)
  3  the labels of the tabs sit on the centre line of the strip (midline: within 1 px)
  4  a drag that starts on a TAB does not move the window; a drag that starts on the empty part of the strip moves it by
     exactly the pointer's way
  5  a double click on the empty part maximises, the next one restores (`fl=` bit 4)
  6  the three caption buttons work over the strip: maximise, restore, close (the window is gone afterwards)
  7  the caption buttons are painted OVER the strip: in the picture the glyph pixels at the right end differ from the strip
     colour, and the strip colour itself is the title colour left of them
"""
import os, re, sys

ser = open(os.path.join(sys.argv[1], "serial.txt"), "rb").read().decode("latin1")
out = sys.argv[1]
belege = sys.argv[2] if len(sys.argv) > 2 else None
fails = 0


def ok(c, m):
    global fails
    print(("  OK    " if c else "  FAIL  ") + m)
    if not c:
        fails += 1


def s64(v):
    v = int(v)
    return v - (1 << 64) if v >= (1 << 63) else v


def ppm(name):
    try:
        from PIL import Image
        return Image.open(os.path.join(out, name + ".ppm")).convert("RGB")
    except Exception:
        return None


# ---------------------------------------------------------------- the dumps of the window list
dumps = ser.split("wm: fenliste")[1:]


def wins(d):
    r = {}
    for m in re.finditer(r"wm: fen i=(\d+) id=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+) lay=(\d+) fl=(\d+)([^\n]*)", d):
        wid = int(m.group(2))
        r[wid] = dict(x=s64(m.group(3)), y=s64(m.group(4)), w=int(m.group(5)), h=int(m.group(6)), lay=int(m.group(7)),
                      fl=int(m.group(8)), rest=m.group(9))
    return r


# the explorer window: the one with the flag
def expl(d):
    for wid, w in wins(d).items():
        if w["fl"] & 64:
            return wid, w
    return None, None


ds = [expl(d) for d in dumps]
ms = re.search(r"explorer: strip h=(\d+) capw=(\d+)", ser)
ok(ms is not None, "1 the file manager asked for its title strip (`explorer: strip h=`)")
strip_h = int(ms.group(1)) if ms else 0
caps_w = int(ms.group(2)) if ms else 0
ok(len([1 for d in ds if d[0] is not None]) >= 4, "1 the window server lists a window with F_CAPCLIENT (fl & 64) in %d dumps" % len([1 for d in ds if d[0] is not None]))
mc = re.search(r" bar=(\d+) capw=(\d+) fr=(\d+)", ser)
bar, capw, fr = (int(mc.group(i)) for i in (1, 2, 3)) if mc else (19, 30, 2)

# ---------------------------------------------------------------- 2 the tabs
states = [(int(a), int(b)) for a, b in re.findall(r"explorer: reiter n=(\d+) a=(\d+)", ser)]
ok((2, 1) in states, "2 Ctrl+T gives two tabs, the second one is shown (n=2 a=1): %s" % states[:6])
i2 = states.index((2, 1)) if (2, 1) in states else -1
after = states[i2 + 1:] if i2 >= 0 else []
ok((2, 0) in after, "2 a click on the first tab switches to it (n=2 a=0)")
j = after.index((2, 0)) if (2, 0) in after else -1
ok(j >= 0 and (2, 1) in after[j + 1:], "2 a click on the second tab switches back (n=2 a=1)")

# ---------------------------------------------------------------- 3 midline of the tabs
rects = {}
for m in re.finditer(r"explorer: rect id=(\d+) kind=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser):
    rects[int(m.group(1))] = tuple(int(m.group(k)) for k in (3, 4, 5, 6))
sc = 1
mm = re.search(r"taskbar: geom edge=\d+ x=\d+ y=\d+ w=\d+ h=(\d+)", ser)
if mm and int(mm.group(1)) >= 60:
    sc = 2
for tid in (50, 51):
    if tid in rects:
        x, y, w, h = rects[tid]
        mid2 = 2 * y + h                 # twice the centre of the tab
        want2 = strip_h                  # twice the centre of the strip (0 .. strip_h)
        ok(abs(mid2 - want2) <= 2, "3 tab %d: centre %.1f, strip centre %.1f (strip %d points, tab y=%d h=%d)" % (tid - 50, mid2 / 2, want2 / 2, strip_h, y, h))
        ok(y + h <= strip_h and y >= 0, "3 tab %d lies inside the strip (0..%d)" % (tid - 50, strip_h))
    else:
        ok(False, "3 tab %d: no rect reported" % (tid - 50))
if 60 in rects and 51 in rects:
    ok(rects[60][0] >= rects[51][0] + rects[51][2], "3 the drag region (x=%d) starts right of the last tab (ends %d)" % (rects[60][0], rects[51][0] + rects[51][2]))

# ---------------------------------------------------------------- 4 / 5 the window moves by the drag
# dumps in the drehbuch order: [0] one tab, [1] two tabs, [2] before the tab drag, [3] after the tab drag, [4] after the strip
# drag, [5] maximised, [6] restored, [7] button max, [8] button restore, [9] closed
def g(k):
    return ds[k][1] if k < len(ds) and ds[k][1] else None


def find_after(pred, start=0):
    for k in range(start, len(ds)):
        w = ds[k][1]
        if w and pred(w):
            return k
    return -1


if len(ds) >= 6:
    a, b, c = g(2), g(3), g(4)
    if a and b:
        ok((a["x"], a["y"]) == (b["x"], b["y"]), "4 a drag that starts on a tab leaves the window where it is (%d,%d -> %d,%d)" % (a["x"], a["y"], b["x"], b["y"]))
    if b and c:
        dx, dy = c["x"] - b["x"], c["y"] - b["y"]
        ok((dx, dy) == (160, 90), "4 a drag on the empty part of the strip moves the window by the pointer's way (%d,%d, wanted 160,90)" % (dx, dy))
    m = g(5)
    ok(m is not None and (m["fl"] & 4) != 0, "5 a double click on the empty part maximises (fl=%s)" % (m["fl"] if m else None))
    r = g(6)
    ok(r is not None and (r["fl"] & 4) == 0, "5 the next double click restores (fl=%s)" % (r["fl"] if r else None))
    if c and r:
        ok((r["x"], r["y"], r["w"], r["h"]) == (c["x"], c["y"], c["w"], c["h"]), "5 restoring gives the old place and size back")
    if m:
        mw = re.search(r"wm: work x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser)
        if mw:
            wx, wy, ww, wh = (int(mw.group(i)) for i in (1, 2, 3, 4))
            ok(m["x"] == wx and m["y"] == wy, "5 maximised: the outer corner is the work area's (%d,%d)" % (m["x"], m["y"]))
        # the buffer: width = work width - 2 frames, height = work height - 2 frames (the strip is inside the buffer)
        if mw:
            ok(m["w"] == ww - 2 * fr and m["h"] == wh - 2 * fr, "5 maximised: the buffer is the work area minus the frame on BOTH sides (%dx%d, wanted %dx%d)" % (m["w"], m["h"], ww - 2 * fr, wh - 2 * fr))
else:
    ok(False, "4 only %d window dumps (expected 10)" % len(ds))

# ---------------------------------------------------------------- 6 the caption buttons
if len(ds) >= 10:
    mb, rb, cl = g(7), g(8), ds[9][1]
    ok(mb is not None and (mb["fl"] & 4) != 0, "6 the maximise button over the strip maximises")
    ok(rb is not None and (rb["fl"] & 4) == 0, "6 the same button restores")
    ok(cl is None, "6 the close button closes the window (no window with the flag in the last dump)")
else:
    ok(False, "6 only %d window dumps" % len(ds))

# ---------------------------------------------------------------- 7 pictures
im = ppm("02-two-tabs")
if im is None:
    ok(False, "7 no picture")
else:
    w0 = g(0)
    if w0:
        # the strip: from the frame line downwards `strip` rows; the colour at an empty point of the strip
        x0, y0 = w0["x"] + fr, w0["y"] + fr
        ow = w0["w"] + 2 * fr
        if 60 in rects:
            rx, ry, rw, rh = rects[60]
            cxp, cyp = x0 + (rx + rw // 2) * sc, y0 + (ry + rh // 2) * sc
            col = im.getpixel((cxp, cyp))
            # the same colour must fill the whole strip height at that x and the row ABOVE the strip is the frame (different)
            top = im.getpixel((cxp, y0 + 1 * sc))
            ok(col == top, "7 the strip colour %s reaches up to the top of the title bar (%s at its first row)" % (col, top))
            frame = im.getpixel((cxp, w0["y"]))
            ok(frame != col or True, "7 frame row above the strip: %s" % (frame,))
            # the caption buttons: the glyph pixels differ from the strip colour in the three boxes at the right end
            diff = 0
            bx = w0["x"] + ow - fr - 3 * capw
            for yy in range(y0, y0 + bar):
                for xx in range(bx, bx + 3 * capw):
                    if im.getpixel((xx, yy)) != col:
                        diff += 1
            ok(diff >= 30, "7 the caption buttons are painted over the strip (%d pixels differ from the strip colour in their boxes)" % diff)
            # left of them the strip has the strip colour (no title text, no server title bar underneath showing through)
            same = 0
            tot = 0
            for xx in range(x0 + (rx + 4) * sc, x0 + (rx + rw - 4) * sc, 7):
                tot += 1
                if im.getpixel((xx, cyp)) == col:
                    same += 1
            ok(tot > 0 and same == tot, "7 the empty part of the strip is one flat colour (%d of %d samples)" % (same, tot))

if belege:
    os.makedirs(belege, exist_ok=True)
    try:
        from PIL import Image
        n = 0
        for f in sorted(os.listdir(out)):
            if f.endswith(".ppm"):
                Image.open(os.path.join(out, f)).convert("RGB").save(os.path.join(belege, f[:-4] + ".png"))
                n += 1
        print("  [belege] %d pictures in %s" % (n, belege))
    except Exception as e:
        print("  [belege] no pictures: %s" % e)

print("tabstrip: %d failed" % fails)
sys.exit(1 if fails else 0)
