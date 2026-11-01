#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    namecheck.py <image.png> <serial.txt> <assets/themes> [<lochbild.png>]
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "ttf"))
import raster                                      # noqa: E402
import fuiraster                                   # noqa: E402

from PIL import Image                              # noqa: E402

FONT = "assets/osum-sans.ttf"
PX_UI = 15

LINE = re.compile(
    r"wlib: text win=(\d+) kind=12 x=(\d+) base=(\d+) fg=(\d+) bg=(\d+)"
    r" tw=(\d+) ax=(\d+) ay=(\d+) nq=(\d+) nv=(\d+) t=(.*)")


def rgb(v):
    return ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)


def glyphkasten(s, name, m):
    x0 = int(m.group(7)) + int(m.group(2))
    base = int(m.group(8)) + int(m.group(3))
    for c, x26 in s.ask(name):
        g = s.glyphe(c)
        if g.w == 0 or g.h == 0:
            continue
        yield c, x0 + (x26 >> 6) + g.left, base - g.top_2, g


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    image, serial, themes = argv[1], argv[2], argv[3]
    roh = open(serial, "rb").read().decode("latin1")
    schnitt = roh.rfind("settings: rect name=waa ")
    tail = roh[schnitt:] if schnitt >= 0 else roh
    gemalt = {}
    for ln in tail.splitlines():
        m = LINE.search(ln)
        if m:
            gemalt[m.group(11)] = m

    soll = {}
    for p in sorted(glob.glob(os.path.join(themes, "*.preset"))):
        for ln in open(p, "rb").read().decode("latin1").splitlines():
            if ln.startswith("name="):
                soll[ln[5:].strip()] = os.path.basename(p)

    im = Image.open(image).convert("RGB")
    s = fuiraster.Font(FONT, PX_UI)

    if len(argv) > 4:
        loch = im.copy()
        gemacht = False
        for name, m in sorted(gemalt.items()):
            if gemacht:
                break
            bg = rgb(int(m.group(5)))
            for c, gx, gy, g in glyphkasten(s, name, m):
                if c != ord("r"):
                    continue
                for j in range(g.h):
                    for i in range(g.w):
                        if 0 <= gx + i < loch.size[0] and 0 <= gy + j < loch.size[1]:
                            loch.putpixel((gx + i, gy + j), bg)
                gemacht = True
                break
        loch.save(argv[4])

    missing = [n for n in soll if n not in gemalt]
    brief = [n for n, m in gemalt.items()
            if m.group(9) != m.group(10)
            or len(n.encode("latin1")) != int(m.group(10))]
    empty_2 = []
    for name, m in sorted(gemalt.items()):
        if name not in soll:
            continue
        fg = rgb(int(m.group(4)))
        bg = rgb(int(m.group(5)))
        for c, gx, gy, g in glyphkasten(s, name, m):
            tinte = 0
            for j in range(g.h):
                for i in range(g.w):
                    if g.a[j * g.w + i] < 128:
                        continue
                    X, Y = gx + i, gy + j
                    if not (0 <= X < im.size[0] and 0 <= Y < im.size[1]):
                        continue
                    p = im.getpixel((X, Y))
                    df = sum(abs(p[k] - fg[k]) for k in range(3))
                    db = sum(abs(p[k] - bg[k]) for k in range(3))
                    if df < db:
                        tinte += 1
            if tinte < 2:
                empty_2.append("%s: '%s' bei x=%d hat %d Tintenpunkte"
                            % (name, chr(c), gx, tinte))
    print("names painted=%d expected=%d missing=%d shortened=%d noink=%d"
          % (len(gemalt), len(soll), len(missing), len(brief), len(empty_2)))
    for z in missing[:5]:
        print("    fehlt: %s" % z)
    for z in brief[:5]:
        print("    gekuerzt: %s" % z)
    for z in empty_2[:5]:
        print("    %s" % z)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
