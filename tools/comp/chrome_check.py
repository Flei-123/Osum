#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
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
    ptr = os.environ.get("PTR", "")
    if ptr:
        qx, qy = (int(v) for v in ptr.split(","))
        if qx - 2 <= px < qx + 16 and qy - 2 <= py < qy + 26:
            return True
    for r in os.environ.get("OCC", "").split(";"):
        if r:
            rx, ry, rw, rh = (int(v) for v in r.split(","))
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
    barh = th - 1 - bo
    print("        window %d,%d %dx%d border=%d title_h=%d capw=%d scale=%d radius=%d grad=%d" % (x, y, ow, oh, bo, th, capw, sk, rad, grad))
    check(0 <= x and 0 <= y and x + ow <= W and y + oh <= H, "the window lies on the screen")
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
    if strip != 1:
        check(abs(run - barh) <= 1, "the title bar is %d rows of the title colour at its middle (the table says %d)" % (run, barh))
    if rad >= 4:
        check(dist(P[x, y], frame_c) >= 12, "the outer corner pixel is not the frame colour (the corner is round): %s vs %s" % (P[x, y], frame_c))
    check(dist(P[xm, y], frame_c) <= 40 or dist(P[xm, y], bar_c) <= tol, "the top edge carries the frame colour: %s" % (P[xm, y],))
    bx = x + ow - bo - 3 * capw
    names = ("minimise", "maximise", "close")
    for n in range(3):
        cx0 = bx + n * capw
        ink = []
        ref = P[cx0 + capw // 2, y + bo + 2]
        ins = 6 * sk
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
    tx0 = x + bo + pad
    tx1 = bx - 4
    ink = []
    for yy in range(y + bo, y + bo + barh):
        for xx in range(tx0, tx1):
            if not occluded(xx, yy) and not occluded(xm, yy) and dist(P[xx, yy], P[xm, yy]) > 80:
                ink.append((xx, yy))
    if strip == 2:
        check(len(ink) >= 30, "the server tab strip: %d ink pixels between the padding and the buttons" % len(ink))
    if not strip:
        check(len(ink) >= 30, "the title text: %d ink pixels between the padding and the buttons" % len(ink))
    if ink and not strip:
        top = min(p[1] for p in ink)
        bot = max(p[1] for p in ink)
        left = min(p[0] for p in ink)
        check(top >= y + bo and bot <= y + bo + barh - 1, "the title text stays inside the bar (rows %d..%d of %d..%d)" % (top, bot, y + bo, y + bo + barh - 1))
        centre = (top + bot) / 2.0
        want = y + bo + barh / 2.0
        check(abs(centre - want) <= 4.0, "the title text is about in the middle of the bar (%.1f vs %.1f)" % (centre, want))
        check(left <= tx0 + 6 * sk, "the title text starts at the left padding (first ink column %d, padding ends %d)" % (left, tx0))
    if hover:
        cx0 = bx + 2 * capw
        face = P[cx0 + 2, y + bo + 2]
        want = rgb(close)
        check(dist(face, want) <= 40, "hover: the close button has its red face %s (want %s)" % (face, want))
    print("PICTURE: %d passed, %d failed" % (PASS, FAIL))
    return FAIL


if __name__ == "__main__":
    sys.exit(main())
