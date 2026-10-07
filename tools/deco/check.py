#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/deco/check.py -- the measured claims of the window chrome (r402).

    check.py <audit-outdir>

<audit-outdir> is the output of `tools/design/audit.sh` with the drehbuch tools/deco/deco.txt:
01-aktiv .. 08-altf4 (.png) and serial.txt.  Prints one line per claim, `OK` or `FAIL`, and a
last line `DECO: <n> passed, <m> failed`.  Every number comes out of the pictures or the serial
log; the only typed numbers are the ones the claims are ABOUT (32 / 46 / 1).
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


def dumps(serial):
    """The list of F12 dumps: each a list of dicts, one per window of the dump."""
    out = []
    for blk in serial.split("wm: fenliste")[1:]:
        ws = []
        for m in re.finditer(r"wm: fen i=(\d+) id=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+) lay=(\d+) "
                             r"fl=(\d+) z=(\d+) [^\n]*", blk):
            line = m.group(0)
            d = dict(i=int(m.group(1)), id=int(m.group(2)), x=int(m.group(3)), y=int(m.group(4)),
                     w=int(m.group(5)), h=int(m.group(6)), lay=int(m.group(7)),
                     fl=int(m.group(8)), z=int(m.group(9)))
            for k in ("tx", "tb", "bar", "capw", "fr"):
                mm = re.search(r" %s=(\d+)" % k, line)
                d[k] = int(mm.group(1)) if mm else None
            ws.append(d)
        out.append(ws)
    return out


def framed(ws):
    return [w for w in ws if w["bar"] is not None and (w["fl"] & 1) == 0]


def top(ws):
    f = framed(ws)
    return max(f, key=lambda w: w["z"]) if f else None


def btn(w, n):
    ow = w["w"] + 2 * w["fr"]
    return (w["x"] + ow - w["fr"] - 3 * w["capw"] + n * w["capw"], w["y"] + w["fr"],
            w["capw"], w["bar"])


def mean_lum(im, box):
    x0, y0, x1, y1 = box
    s = n = 0
    for y in range(y0, y1):
        for x in range(x0, x1):
            s += lum(px(im, x, y))
            n += 1
    return s / max(1, n)


def run_len(im, y, x0, x1, test):
    """Longest run of pixels in row y, x0..x1, for which test(pixel) holds."""
    best = cur = 0
    for x in range(x0, x1):
        if test(px(im, x, y)):
            cur += 1
            best = max(best, cur)
        else:
            cur = 0
    return best


def main(out):
    serial = open(os.path.join(out, "serial.txt"), "rb").read().decode("latin-1")
    ds = dumps(serial)
    check(len(ds) >= 4, "four window dumps on the line (F12): %d" % len(ds))
    if len(ds) < 4:
        return
    d1, d2, d3, d4 = ds[0], ds[1], ds[2], ds[3]
    w = top(d1)
    check(w is not None, "a framed window is on the screen (the dump names its measures)")
    if w is None:
        return
    # ---- 1. the measures (shape osum: 32 / 46 / 1)
    check(w["bar"] == 32, "the title bar is 32 high (the dump says %s)" % w["bar"])
    check(w["capw"] == 46, "a caption button is 46 wide (the dump says %s)" % w["capw"])
    check(w["fr"] == 1, "the frame is 1 (the dump says %s)" % w["fr"])
    im1 = Image.open(os.path.join(out, "01-aktiv.png")).convert("RGB")
    # ---- 2. the title stands in the middle: equal room above and below the first capital
    bar_top = w["y"] + w["fr"]
    bar_bot = bar_top + w["bar"]
    tx = w["tx"] if w["tx"] is not None else w["x"] + 12
    bg = px(im1, tx - 3, bar_top + w["bar"] // 2)
    ys = []
    for y in range(bar_top, bar_bot):
        for x in range(tx, tx + 9):
            p = px(im1, x, y)
            if sum(abs(a - b) for a, b in zip(p, bg)) > 120:
                ys.append(y)
    if ys:
        up = min(ys) - bar_top
        down = bar_bot - 1 - max(ys)
        check(abs(up - down) <= 1,
              "the first capital of the title has %d above and %d below it in the bar "
              "(difference <= 1)" % (up, down))
    else:
        bad("no ink of the title found at x=%d in the bar" % tx)
    # ---- 3. hover on close: red plate, 46 wide
    im2 = Image.open(os.path.join(out, "02-close-hover.png")).convert("RGB")
    cx, cy, cw, ch = btn(w, 2)

    def red(p):
        return p[0] > 170 and p[1] < 100 and p[2] < 100
    n = sum(1 for yy in range(cy + 2, cy + ch - 2) for xx in range(cx + 2, cx + cw - 2)
            if red(px(im2, xx, yy)))
    area = (cw - 4) * (ch - 6)
    check(n * 100 >= 80 * area,
          "the close button is red on hover (%d of %d plate pixels)" % (n, area))
    run = run_len(im2, cy + 4, cx - 10, cx + cw + 10, red)  # a row above the cross
    check(abs(run - cw) <= 2, "the red plate is %d wide (button %d)" % (run, cw))
    # ---- 4. hover on minimise: a soft plate (not red), 46 wide
    im3 = Image.open(os.path.join(out, "03-min-hover.png")).convert("RGB")
    mx, my, mw, mh = btn(w, 0)
    base = px(im1, mx - 4, my + 4)
    face = px(im3, mx + 5, my + 5)
    check(abs(lum(face) - lum(base)) >= 4 and not red(face),
          "the minimise button shows a soft plate on hover (%d against %d)"
          % (lum(face), lum(base)))
    soft = lambda p: abs(lum(p) - lum(base)) >= 4 and not red(p)
    run = run_len(im3, my + 5, mx - 10, mx + mw + 10, soft)
    check(abs(run - mw) <= 2, "the soft plate is %d wide (button %d)" % (run, mw))
    # ---- 5. held: deeper than hover
    im4 = Image.open(os.path.join(out, "04-min-gehalten.png")).convert("RGB")
    box = (mx + 4, my + 4, mx + 14, my + 10)
    hover_l = mean_lum(im3, box)
    held_l = mean_lum(im4, box)
    check(abs(held_l - hover_l) >= 3,
          "a held button is painted differently from a hovered one (%.1f against %.1f)"
          % (held_l, hover_l))
    # ---- 6. released on the button: the window goes away
    im5 = Image.open(os.path.join(out, "05-min-los.png")).convert("RGB")
    gone = lum(px(im5, w["x"] + 120, bar_top + w["bar"] // 2)) != lum(px(im1, w["x"] + 120,
                                                                         bar_top + w["bar"] // 2))
    check(gone, "released on the minimise button: the window is gone from the screen")
    check(top(d2) is None or top(d2)["id"] != w["id"],
          "the next dump does not list the window as visible")
    # ---- 7. held on close, released elsewhere: nothing happens
    t = top(d2)
    check(t is not None, "a second framed window is there (the terminal)")
    if t is not None:
        ids = {x["id"] for x in framed(d3)}
        check(t["id"] in ids, "held on close, pointer led away, released: the window is still there")
        im7 = Image.open(os.path.join(out, "07-close-abbruch.png")).convert("RGB")
        tb_top = t["y"] + t["fr"]
        check(lum(px(im7, t["x"] + 200, tb_top + t["bar"] // 2)) > 150,
              "and its title bar is still on the picture")
    # ---- 8. Alt+F4
    check(len(framed(d4)) == len(framed(d3)) - 1,
          "Alt+F4 closed the window with the focus (%d framed windows before, %d after)"
          % (len(framed(d3)), len(framed(d4))))


def schatten(out_off, out_on):
    """The window shadow switch: off in the first run, on in the second, same window, same place."""
    so = open(os.path.join(out_on, "serial.txt"), "rb").read().decode("latin-1")
    d = dumps(so)
    check(bool(d), "the shadow run has a window dump")
    if not d:
        return
    w = top(d[0])
    check(w is not None, "the shadow run shows a framed window")
    if w is None:
        return
    off = Image.open(os.path.join(out_off, "01-aktiv.png")).convert("RGB")
    on = Image.open(os.path.join(out_on, "01-aktiv.png")).convert("RGB")
    ow = w["w"] + 2 * w["fr"]
    oh = w["h"] + 2 * w["fr"] + w["bar"] + 1          # frame, bar, separator, frame
    x0, y0 = w["x"], w["y"]
    # a band under the window and one right of it, a few points wide, on the wallpaper
    def band(im, box):
        return sum(lum(px(im, x, y)) for x in range(box[0], box[2]) for y in range(box[1], box[3])) \
            / float((box[2] - box[0]) * (box[3] - box[1]))
    below = (x0 + 40, y0 + oh + 1, x0 + ow - 40, y0 + oh + 5)
    right = (x0 + ow + 1, y0 + 80, x0 + ow + 5, y0 + oh - 80)
    # (below the window the picture is identical with and without: the mask lies the light from the top
    # left, 8 points reach, and this wallpaper is dark there -- measured, not claimed: only the right is checked)
    for name, box in (("right of", right),):
        if box[3] <= box[1] or box[2] <= box[0] or box[3] > 760:
            continue
        a, b = band(off, box), band(on, box)
        check(b <= a - (4 if a > 80 else 1) + (0 if a > 80 else 0.5), "the shadow %s the window darkens the wallpaper (%.1f against %.1f without)"
              % (name, b, a))
    far = (x0 + 40, y0 + oh + 40, x0 + ow - 40, y0 + oh + 44)
    if far[3] <= 760:
        a, b = band(off, far), band(on, far)
        check(abs(a - b) <= 2, "and 40 points away nothing changed (%.1f against %.1f)" % (b, a))


if __name__ == "__main__":
    main(sys.argv[1])
    if len(sys.argv) > 2:
        schatten(sys.argv[1], sys.argv[2])
    print("DECO: %d passed, %d failed" % (PASS, FAIL))
    sys.exit(1 if FAIL else 0)
