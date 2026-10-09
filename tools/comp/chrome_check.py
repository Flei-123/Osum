#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/comp/chrome_check.py <picture.ppm> <chrome-geo numbers...> [hover]

The INDEPENDENT eye of tools/comp/chrome.sh (docs/COMPOSITOR.md, S6b). `wmd` judges its own picture against the kernel's and says "0 differ";
that is worth nothing when both share a bug (S6a: both drew the shadow too far out). So this reads only the kernel's SCREENSHOT and asks what a
person asks: is there a title bar of the right height and colour, does the title text stand inside it (not cut, roughly in the middle), do the
three buttons carry a symbol in the middle of their cell, is the corner round, and (hover) is the close button red?

The numbers come from the line `wmd: chrome-geo focused own_strip x y ow oh border title_h cap_w scale radius title frame text pad grad close`;
the colours are 0xRRGGBB as decimals. A window that paints its own strip (own_strip = 1, the file manager's tabs) has no server title bar or text:
only its buttons, corner and top edge are checked. Prints OK / FAIL lines; the exit code is the number of failures."""
import os
import sys

from PIL import Image

PASS = FAIL = 0


def check(c, m):
    global PASS, FAIL
    if c:
        PASS += 1
    else:
        FAIL += 1
    print(("  OK    " if c else "  FAIL  ") + m)


def rgb(v):
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


def dist(a, b):
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))


def occluded(px, py, margin=0):
    """True when (px, py) lies inside the rectangle of ANOTHER window (env OCC = "x,y,w,h;..."): not this window's pixel."""
    ptr = os.environ.get("PTR", "")
    if ptr:
        qx, qy = (int(v) for v in ptr.split(","))
        if qx - 2 <= px < qx + 16 and qy - 2 <= py < qy + 26:     # the pointer arrow
            return True
    for r in os.environ.get("OCC", "").split(";"):
        if r:
            rx, ry, rw, rh = (int(v) for v in r.split(","))
            # (with a margin: the other window's shadow reaches 8 to 16 points around it)
            if rx - margin <= px < rx + rw + margin and ry - margin <= py < ry + rh + margin:
                return True
    return False


def main():
    path = sys.argv[1]
    nums = [int(v) for v in sys.argv[2:19]]
    hover = len(sys.argv) > 19 and sys.argv[19] == "hover"
    focused, strip, x, y, ow, oh, bo, th, capw, sk, rad, title, frame, text, pad, grad, close = nums
    im = Image.open(path).convert("RGB")
    W, H = im.size
    P = im.load()
    bar_c = rgb(title)
    frame_c = rgb(frame)
    tol = grad + 6
    barh = th - 1 - bo                      # rows of the bar
    print("        window %d,%d %dx%d border=%d title_h=%d capw=%d scale=%d radius=%d grad=%d" % (x, y, ow, oh, bo, th, capw, sk, rad, grad))
    check(0 <= x and 0 <= y and x + ow <= W and y + oh <= H, "the window lies on the screen")
    # 1. the bar: a run of rows of the title colour (the gradient darkens the first rows by up to `grad`), as high as the table says
    xm = x + ow // 2
    run = 0
    for yy in range(y + bo, y + th + 4):
        if occluded(xm, yy, 20):
            run = barh
            break
        if dist(P[xm, yy], bar_c) <= tol:
            run += 1
        else:
            break
    if not strip:
        check(abs(run - barh) <= 1, "the title bar is %d rows of the title colour at its middle (the table says %d)" % (run, barh))
    # 2. the rounded corner: the outer corner pixel is not the frame colour (a square corner would be)
    if rad >= 4:
        check(dist(P[x, y], frame_c) >= 12, "the outer corner pixel is not the frame colour (the corner is round): %s vs %s" % (P[x, y], frame_c))
    check(dist(P[xm, y], frame_c) <= 40 or dist(P[xm, y], bar_c) <= tol, "the top edge carries the frame colour: %s" % (P[xm, y],))
    # 3. the three buttons: a symbol in the middle of each cell
    bx = x + ow - bo - 3 * capw
    names = ("minimise", "maximise", "close")
    for n in range(3):
        cx0 = bx + n * capw
        ink = []
        # the cell's own face colour: sampled at the cell's top left corner inside the bar (the pointer is elsewhere; the face is the bar)
        ref = P[cx0 + capw // 2, y + bo + 2]
        ins = 6 * sk      # keep away from the cell edge: the close button's corner is round, outside it lies the wallpaper
        for yy in range(y + bo + ins // 2, y + bo + barh - ins // 2):
            for xx in range(cx0 + ins, cx0 + capw - ins):
                if not occluded(xx, yy) and dist(P[xx, yy], ref) > 90:
                    ink.append((xx, yy))
        if n == 2 and hover:
            ink = [(xx, yy) for (xx, yy) in ink if dist(P[xx, yy], rgb(close)) > 60]
        check(len(ink) >= 8 * sk, "%s button: %d ink pixels" % (names[n], len(ink)))
        if ink:
            mx = (min(p[0] for p in ink) + max(p[0] for p in ink)) / 2.0
            my = (min(p[1] for p in ink) + max(p[1] for p in ink)) / 2.0
            check(abs(mx - (cx0 + capw / 2.0 - 0.5)) <= 2.0 and abs(my - (y + bo + barh / 2.0 - 0.5)) <= 2.0,
                  "%s symbol is centred in its cell (dx=%.1f dy=%.1f)" % (names[n], mx - (cx0 + capw / 2.0 - 0.5), my - (y + bo + barh / 2.0 - 0.5)))
    # 4. the title text: ink between the left padding and the buttons, inside the bar, roughly centred vertically
    tx0 = x + bo + pad
    tx1 = bx - 4
    ink = []
    for yy in range(y + bo, y + bo + barh):
        for xx in range(tx0, tx1):
            if not occluded(xx, yy) and not occluded(xm, yy) and dist(P[xx, yy], P[xm, yy]) > 80:
                ink.append((xx, yy))
    if not strip:
        check(len(ink) >= 30, "the title text: %d ink pixels between the padding and the buttons" % len(ink))
    if ink and not strip:
        top = min(p[1] for p in ink)
        bot = max(p[1] for p in ink)
        left = min(p[0] for p in ink)
        check(top >= y + bo and bot <= y + bo + barh - 1, "the title text stays inside the bar (rows %d..%d of %d..%d)" % (top, bot, y + bo, y + bo + barh - 1))
        centre = (top + bot) / 2.0
        want = y + bo + barh / 2.0
        # descenders and capitals make the ink box differ from the line box by a few pixels
        check(abs(centre - want) <= 4.0, "the title text is about in the middle of the bar (%.1f vs %.1f)" % (centre, want))
        check(left <= tx0 + 6 * sk, "the title text starts at the left padding (first ink column %d, padding ends %d)" % (left, tx0))
    # 5. hover: the close button's face is red
    if hover:
        cx0 = bx + 2 * capw
        face = P[cx0 + 2, y + bo + 2]
        want = rgb(close)
        check(dist(face, want) <= 40, "hover: the close button has its red face %s (want %s)" % (face, want))
    print("PICTURE: %d passed, %d failed" % (PASS, FAIL))
    return FAIL


if __name__ == "__main__":
    sys.exit(main())
