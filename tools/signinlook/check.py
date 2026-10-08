#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/signinlook/check.py -- r470: THE SIGN-IN AND LOCK SCREEN IN NUMBERS.

    check.py <dir of one capture> <glogin|lock> <label>

<dir> holds `desktop.ppm` (the screenshot) and `serial.txt` (the program's
`rect` lines). Every judgement is a measured contrast ratio (WCAG 2.x
relative luminance), not a look at the picture:

  text      name, status line, hint, user chip, clock, language: the known
            text colour against the 90th percentile of the luminance of the
            non-text pixels under the text box (the worst part of the
            background). >= 4.5 for text under 24 px, >= 3.0 for the name
            (24 px bold, "large text"). Also: the text is there (enough ink
            pixels) and does not touch the edge of its box (not clipped).
  glyph     eye, sign-in arrow, network, power: the strongest pixel of the
            tile against the tile's own face (median), >= 3.0
            (WCAG 1.4.11, graphics).
  label     the "Anderer Benutzer" button: label against its face, >= 4.5.
  glass     network/power plate against the picture next to it: the plate
            must be visible (>= 1.15 to 1).
  field     the password field: the typed dots against the field (>= 4.5);
            the field's edge (face or rim, whichever is stronger) against the
            picture around it (>= 2.0: a dark field on a dimmed photo; the
            focus ring and the dots carry the rest).
  scene     the picture is not blank (>= 250 distinct colours).

Prints `  OK    ...` / `  FAIL  ...` lines and `SIGNINLOOK <label>: n passed,
m failed`; exit status 1 when something failed.
"""
import re
import sys

from PIL import Image

WHITE = (255, 255, 255)
SOFT = (0xDC, 0xE6, 0xF5)


def lin(v):
    v /= 255.0
    return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4


def lum(c):
    return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])


def cr(a, b):
    la, lb = lum(a), lum(b)
    if la < lb:
        la, lb = lb, la
    return (la + 0.05) / (lb + 0.05)


def rect_pixels(im, x, y, w, h, inset=0):
    out = []
    x0, y0 = max(0, x + inset), max(0, y + inset)
    x1, y1 = min(im.width, x + w - inset), min(im.height, y + h - inset)
    for j in range(y0, y1):
        for i in range(x0, x1):
            out.append(im.getpixel((i, j)))
    return out


def median_col(px):
    ch = [sorted(p[k] for p in px) for k in range(3)]
    n = len(px)
    return tuple(ch[k][n // 2] for k in range(3))


def percentile(vals, q):
    vals = sorted(vals)
    if not vals:
        return 0.0
    return vals[min(len(vals) - 1, int(len(vals) * q))]


class Report:
    def __init__(self, label):
        self.label = label
        self.ok = 0
        self.bad = 0

    def put(self, good, text):
        if good:
            self.ok += 1
            print("  OK    %s" % text)
        else:
            self.bad += 1
            print("  FAIL  %s" % text)


def text_check(rp, im, name, box, fg, need):
    x, y, w, h = box
    px = rect_pixels(im, x, y, w, h)
    if not px:
        rp.put(False, "%s: box outside the picture %s" % (name, box))
        return
    lt = lum(fg)
    # the background: everything clearly darker than the text colour
    bgl = [lum(p) for p in px if lum(p) < lt * 0.8]
    if len(bgl) < len(px) // 4:
        rp.put(False, "%s: no background found" % name)
        return
    bg_l = percentile(bgl, 0.9)
    ratio = (lt + 0.05) / (bg_l + 0.05)
    # ink pixels: halfway between the background and the text colour or more
    thr = bg_l + (lt - bg_l) * 0.5
    xs, ys, n = [], [], 0
    for j in range(h):
        for i in range(w):
            if x + i >= im.width or y + j >= im.height:
                continue
            if lum(im.getpixel((x + i, y + j))) >= thr:
                n += 1
                xs.append(i)
                ys.append(j)
    rp.put(ratio >= need, "%s: contrast %.2f to 1 (need >= %.1f)" % (name, ratio, need))
    rp.put(n >= 20, "%s: text present (%d ink pixels)" % (name, n))
    if n:
        clip = min(xs) == 0 or min(ys) == 0 or max(xs) == w - 1 or max(ys) == h - 1
        rp.put(not clip, "%s: not cut off (ink %d..%d x %d..%d in %dx%d)"
               % (name, min(xs), max(xs), min(ys), max(ys), w, h))


def face_and_glyph(im, box):
    x, y, w, h = box
    px = rect_pixels(im, x, y, w, h, inset=4)
    face = median_col(px)
    vals = sorted(cr(p, face) for p in px)
    # strongest ~2 per cent of the pixels: the glyph's core, not one stray pixel
    return face, vals[min(len(vals) - 1, int(len(vals) * 0.985))]


def read_rects(serial, prefix):
    rects = {}
    for m in re.finditer(r"%s: rect id=(\d+) kind=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % prefix,
                         open(serial, "rb").read().decode("latin1")):
        rects[int(m.group(1))] = tuple(int(m.group(k)) for k in range(3, 7))
    return rects


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    d, app, label = sys.argv[1], sys.argv[2], sys.argv[3]
    im = Image.open(d + "/desktop.ppm").convert("RGB")
    rp = Report(label)
    R = read_rects(d + "/serial.txt", "glogin" if app == "glogin" else "lock")
    if app == "glogin":
        need = (1, 2, 7, 8, 9, 10, 11, 12)
        miss = [i for i in need if i not in R]
        if miss:
            rp.put(False, "rects missing: %s" % miss)
            print("SIGNINLOOK %s: %d passed, %d failed" % (label, rp.ok, rp.bad))
            return 1
        status, name, entry, arrow = R[1], R[2], R[7], R[8]
        other, clock, net, power = R[9], R[10], R[11], R[12]
        chip = (other[0] + 44, other[1] - 40, 192, 36)
        hint = None
    else:
        need = (11, 12, 13, 25)
        miss = [i for i in need if i not in R]
        if miss:
            rp.put(False, "rects missing: %s" % miss)
            print("SIGNINLOOK %s: %d passed, %d failed" % (label, rp.ok, rp.bad))
            return 1
        entry, arrow, power = R[11], R[13], R[25]
        name = (entry[0], entry[1] - 80, 320, 36)
        status = (entry[0], entry[1] - 44, 320, 32)
        hint = (entry[0] - 40, entry[1] + 40, 400, 40)
        net = (power[0] - 36, power[1], 36, 36)
        chip = (76, power[1], 170, 36)
        clock = None
        other = None
    eye = (entry[0] + entry[2] + 4, entry[1], 36, 36)
    lang = (net[0] - 44, net[1], 44, 36)

    # ---- text
    text_check(rp, im, "name", name, WHITE, 3.0)
    text_check(rp, im, "status", status, WHITE, 4.5)
    if hint is not None:
        text_check(rp, im, "hint", hint, SOFT, 4.5)
    text_check(rp, im, "user chip", chip, WHITE, 4.5)
    if clock is not None:
        text_check(rp, im, "clock", clock, WHITE, 4.5)
    text_check(rp, im, "language", lang, WHITE, 4.5)

    # ---- glyphs on their faces
    for nm, box in (("eye", eye), ("arrow", arrow), ("network", net), ("power", power)):
        face, c = face_and_glyph(im, box)
        rp.put(c >= 3.0, "%s glyph: %.2f to 1 on its face %s (need >= 3.0)" % (nm, c, face))
    if other is not None:
        face, c = face_and_glyph(im, other)
        rp.put(c >= 4.5, "'Anderer Benutzer' label: %.2f to 1 on %s (need >= 4.5)" % (c, face))

    # ---- milk glass: the plate has to be seen against the picture next to it
    for nm, box in (("network", net), ("power", power)):
        x, y, w, h = box
        plate = median_col(rect_pixels(im, x, y, w, h, inset=4))
        if x + w + 4 >= im.width:
            side = rect_pixels(im, x - 4, y + 4, 3, h - 8)
        else:
            side = rect_pixels(im, x + w + 1, y + 4, 3, h - 8)
        if nm == "network":
            side = rect_pixels(im, x - 4, y + 4, 3, h - 8)
        bg = median_col(side)
        c = cr(plate, bg)
        rp.put(c >= 1.15, "glass %s: plate %s against the picture %s: %.2f to 1 (need >= 1.15)"
               % (nm, plate, bg, c))

    # ---- the password field
    ex, ey, ew, eh = entry
    inner = rect_pixels(im, ex, ey, ew, eh, inset=5)
    fill = median_col(inner)
    dots = sorted(cr(p, fill) for p in inner)
    dotc = dots[min(len(dots) - 1, int(len(dots) * 0.998))]   # three small dots: the top ~12 pixels
    rp.put(dotc >= 4.5, "field: typed dots %.2f to 1 on the field %s (need >= 4.5)" % (dotc, fill))
    around = rect_pixels(im, ex - 8, ey - 8, ew + 16, 6) + rect_pixels(im, ex - 8, ey + eh + 2, ew + 16, 6)
    out = median_col(around)
    rim = median_col(rect_pixels(im, ex + 20, ey, ew - 40, 2) + rect_pixels(im, ex + 20, ey + eh - 2, ew - 40, 2))
    edge = max(cr(fill, out), cr(rim, out))
    rp.put(edge >= 2.0, "field: edge %.2f to 1 against the picture %s (need >= 2.0)" % (edge, out))

    # ---- not blank
    cols = set()
    for j in range(0, im.height, 4):
        for i in range(0, im.width, 4):
            cols.add(im.getpixel((i, j)))
    rp.put(len(cols) >= 250, "picture: %d distinct colours (need >= 250; the flat gradient has ~300)" % len(cols))

    print("SIGNINLOOK %s: %d passed, %d failed" % (label, rp.ok, rp.bad))
    return 0 if rp.bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
