#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

from PIL import Image

INK_DELTA = 90
INK_MIN = 8


def ink(im):
    bg = im.getpixel((0, 0))
    count = 0
    for y in range(im.height):
        for x in range(im.width):
            p = im.getpixel((x, y))
            if sum(abs(p[i] - bg[i]) for i in range(3)) >= INK_DELTA:
                count += 1
    return count


def live_box(out):
    ser = open(os.path.join(out, "serial.txt"), "rb").read().decode("latin1")
    rects = {int(m.group(1)): tuple(int(m.group(k)) for k in (2, 3, 4, 5))
             for m in re.finditer(r"explorer: rect id=(\d+) kind=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser)}
    dumps = ser.split("wm: fenliste")[1:]
    win = None
    for m in re.finditer(r"wm: fen i=\d+ id=\d+ x=(\d+) y=(\d+) w=\d+ h=\d+ lay=\d+ fl=(\d+)", dumps[-1] if dumps else ""):
        if int(m.group(3)) & 64:
            win = (int(m.group(1)), int(m.group(2)))
    mc = re.search(r" bar=\d+ capw=\d+ fr=(\d+)", ser)
    frame = int(mc.group(1)) if mc else 2
    if win is None or 50 not in rects or 60 not in rects:
        return None
    tab, drag = rects[50], rects[60]
    x0, y0 = win[0] + frame, win[1] + frame
    return (x0 + tab[0] + tab[2], y0 + drag[1], x0 + drag[0], y0 + drag[1] + drag[3])


def main():
    out = sys.argv[1]
    fails = 0

    def check(cond, msg):
        nonlocal fails
        print(("  OK    " if cond else "  FAIL  ") + msg)
        fails += 0 if cond else 1

    box = live_box(out)
    check(box is not None, "the window dump and the strip rectangles are in the serial log")
    if box:
        im = Image.open(os.path.join(out, "01-inactive.ppm")).convert("RGB").crop(box)
        live = ink(im)
        check(live >= INK_MIN, "the plus button of the INACTIVE window strip is visible (%d ink pixels in %s)" % (live, box))
    print("inactive: %d failed" % fails)
    sys.exit(1 if fails else 0)


main()
