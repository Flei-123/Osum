#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    read.py -- den INHALT des Terminalfensters aus einem photo read_all.
    python3 read.py <ppm> [--x0 N --y0 N --cols N --rows N --cw N --ch N]
"""
import os
import sys

from PIL import Image

HIER = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HIER, ".."))
sys.path.insert(0, os.path.join(REPO, "tools", "ttf"))
import raster  # noqa: E402

MONO = os.path.join(REPO, "assets", "osum-mono.ttf")
CHARS = (" !\"#$%&'()*+,-./0123456789:;<=>?@"
           "ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`"
           "abcdefghijklmnopqrstuvwxyz{|}~"
           "äöüÄÖÜß")


def muster(px, cw, ch, reason):
    """Je Zeichen sein Bild in der Zelle: Menge der gesetzten Punkte."""
    s = raster.Font(MONO, px)
    aus = {}
    for c in CHARS:
        g = s.glyphe(ord(c))
        pk = set()
        if g.w and g.h:
            for r in range(g.h):
                for k in range(g.w):
                    if g.punkt(k, r) >= 128:
                        x = g.left + k
                        y = reason - g.top + r
                        if 0 <= x < cw and 0 <= y < ch:
                            pk.add((x, y))
        aus[c] = pk
    return aus


def cell_points(im, x0, y0, cw, ch, tinte=(0, 255, 102)):
    """Die gesetzten Punkte einer Zelle.

    NUR DIE TINTENFARBE ZAEHLT, nicht "hell genug". Das Terminal des
    Kerns malt gruen (0,255,102) auf schwarz; der Fensterrahmen daneben
    ist hellblau und die Leiste grau. Eine Helligkeitsschwelle nimmt
    beides mit, und dann steht in jeder Randzelle ein Zeichen, das dort
    nicht ist. Der Zeichensatz kennt seine Farbe -- also wird sie
    verlangt."""
    b = im.load()
    w, h = im.size
    pk = set()
    for y in range(ch):
        for x in range(cw):
            xx, yy = x0 + x, y0 + y
            if xx >= w or yy >= h:
                continue
            if b[xx, yy] == tinte:
                pk.add((x, y))
    return pk


def read_text(ppm, x0=26, y0=62, cols=56, rows=20, cw=10, ch=19, px=16,
         reason=14):
    im = Image.open(ppm).convert("RGB")
    mus = muster(px, cw, ch, reason)
    line_rows = []
    for r in range(rows):
        text = ""
        for c in range(cols):
            pk = cell_points(im, x0 + c * cw, y0 + r * ch, cw, ch)
            if len(pk) < 3:
                text += " "
                continue
            bester, value = " ", -1.0
            for chars, mp in mus.items():
                if not mp and not pk:
                    continue
                if not mp:
                    continue
                treffer = len(pk & mp)
                missing = len(pk ^ mp)
                w = treffer - 0.55 * missing
                if w > value:
                    value, bester = w, chars
            text += bester
        line_rows.append(text.rstrip())
    return line_rows


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    d = {"x0": 26, "y0": 62, "cols": 56, "rows": 20, "cw": 10, "ch": 19,
         "px": 16, "grund": 14}
    for i, a in enumerate(argv):
        if a.startswith("--") and a[2:] in d and i + 1 < len(argv):
            d[a[2:]] = int(argv[i + 1])
    for i, z in enumerate(read_text(argv[1], **d)):
        if z.strip():
            print("%2d | %s" % (i, z))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
