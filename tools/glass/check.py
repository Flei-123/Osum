#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/glass/check.py -- W-GLASS: THE FROSTED GLASS OF THE LOCK AND SIGN-IN SCREEN, IN PIXELS.

    check.py field <dir of one capture> <glogin|lock> <label> [flat]
    check.py caret <dir of a burst series> <prefix> <x0> <y0> <x1> <y1> <dark|light>

field: <dir> holds `desktop.ppm` and `serial.txt` (the program's `rect` lines, tools/signinlook).
  variance  the field's face (left and right of the typed dots, inset 4) is NOT a flat fill: the standard
            deviation of its luminance is >= 0.8 levels (blurred wallpaper + grain show through the tint). A flat
            plate has 0.
  soft      ... and it is smooth, not noise: the mean difference of horizontal neighbours is <= 3.0 levels.
  border    a thin light rim: the mean luminance of the top edge rows is >= 3 levels above the row 5 px inside.
  surround  the plate is visible against the picture around it (luminance ratio >= 1.3).
  With `flat` (the control run /etc/noglass) the variance check must FAIL: the script then prints
  `GLASS <label>: control red` and exits 0; if it does not turn red it exits 1 (the check is blind).
caret: per frame of a burst series: is a caret bar (a thin vertical bar of the ink colour, >= 55 % of the
  field's inner height) inside the box? Needs frames with a bar AND frames without one.
"""
import glob
import os
import re
import sys

from PIL import Image


def lum8(p):
    return (p[0] * 3 + p[1] * 6 + p[2]) / 10.0


def rects(serial, prefix):
    out = {}
    t = open(serial, "rb").read().decode("latin1")
    for m in re.finditer(r"%s: rect id=(\d+) kind=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % prefix, t):
        out[int(m.group(1))] = tuple(int(m.group(k)) for k in range(3, 7))
    return out


def mean(v):
    return sum(v) / max(1, len(v))


def field_metrics(im, box):
    x, y, w, h = box
    # the face: top and bottom band of the interior (the dots sit in the middle), without the corners
    vals = []
    adj = []
    for j in list(range(y + 4, y + 9)) + list(range(y + h - 9, y + h - 4)):
        row = [lum8(im.getpixel((i, j))) for i in range(x + 20, x + w - 20)]
        vals += row
        adj += [abs(row[k + 1] - row[k]) for k in range(len(row) - 1)]
    m = mean(vals)
    sd = (mean([(v - m) ** 2 for v in vals])) ** 0.5
    rim = mean([lum8(im.getpixel((i, j))) for j in (y, y + 1) for i in range(x + 20, x + w - 20)])
    inner = mean([lum8(im.getpixel((i, y + 5))) for i in range(x + 20, x + w - 20)])
    out_ = mean([lum8(im.getpixel((i, j))) for j in range(y - 9, y - 4) for i in range(x + 20, x + w - 20)])
    return {"sd": sd, "adj": mean(adj), "rim": rim, "inner": inner, "out": out_, "face": m}


def cmd_field(a):
    d, app, label = a[0], a[1], a[2]
    flat = len(a) > 3 and a[3] == "flat"
    im = Image.open(d + "/desktop.ppm").convert("RGB")
    R = rects(d + "/serial.txt", "glogin" if app == "glogin" else "lock")
    key = 7 if app == "glogin" else 11
    if key not in R:
        print("  FAIL  %s: the program did not report its password field" % label)
        return 1
    m = field_metrics(im, R[key])
    ok = bad = 0
    res = []
    res.append((m["sd"] >= 0.8, "variance: the field face is not a flat fill (std %.2f levels, need >= 0.8)" % m["sd"]))
    res.append((m["adj"] <= 3.0, "soft: neighbour difference %.2f (need <= 3.0: blurred, not noisy)" % m["adj"]))
    res.append((m["rim"] - m["inner"] >= 3.0, "border: rim %.1f vs inside %.1f (need >= +3)" % (m["rim"], m["inner"])))
    ratio = (max(m["face"], m["out"]) + 12.0) / (min(m["face"], m["out"]) + 12.0)
    res.append((ratio >= 1.3, "surround: plate %.1f vs picture around %.1f (ratio %.2f, need >= 1.3)" % (m["face"], m["out"], ratio)))
    if flat:
        red = not res[0][0]
        print("  %s  control %s: the variance check %s (std %.2f)" % ("OK  " if red else "FAIL", label,
              "turned red" if red else "stayed green -- blind", m["sd"]))
        print("GLASS %s: control %s" % (label, "red" if red else "NOT red"))
        return 0 if red else 1
    for good, text in res:
        print("  %s  %s: %s" % ("OK  " if good else "FAIL", label, text))
        ok += good
        bad += (not good)
    print("GLASS %s: %d passed, %d failed" % (label, ok, bad))
    return 1 if bad else 0


def read_ppm(path):
    return Image.open(path).convert("RGB")


def bar_in(im, box, mode):
    x0, y0, x1, y1 = box
    hh = y1 - y0
    cols = []
    for i in range(x0, x1):
        n = 0
        for j in range(y0, y1):
            l = lum8(im.getpixel((i, j)))
            if (mode == "light" and l < 110) or (mode == "dark" and l > 200):
                n += 1
        cols.append(n >= max(6, int(0.55 * hh)))
    run = 0
    for c in cols:
        run = run + 1 if c else 0
        if run > 3:
            return False
    return any(cols)


def cmd_caret(a):
    d, pre = a[0], a[1]
    box = tuple(int(v) for v in a[2:6])
    mode = a[6]
    files = sorted(glob.glob(os.path.join(d, pre + "-[0-9][0-9][0-9].ppm")))
    st = [1 if bar_in(read_ppm(f), box, mode) else 0 for f in files]
    tr = sum(1 for i in range(1, len(st)) if st[i] != st[i - 1])
    print("FRAMES %d" % len(st))
    print("STATE " + "".join(str(v) for v in st))
    print("TRANSITIONS %d" % tr)
    print("ONFRAMES %d" % sum(st))
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    sys.exit({"field": cmd_field, "caret": cmd_caret}[sys.argv[1]](sys.argv[2:]))
