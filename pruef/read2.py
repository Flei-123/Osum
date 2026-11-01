#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    read2.py -- den Text im Terminalfenster read_all, auch bei 2x-image.
    python3 read2.py <ppm> [--x0 N --y0 N --skala N --cols N --rows N]
"""
import os
import sys

from PIL import Image

HIER = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HIER, ".."))
sys.path.insert(0, os.path.join(REPO, "tools", "ttf"))
import raster  # noqa: E402

MONO = os.path.join(REPO, "assets", "osum-mono.ttf")
TINTE = (0, 255, 102)
CHARS = (" !\"#$%&'()*+,-./0123456789:;<=>?@"
           "ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`"
           "abcdefghijklmnopqrstuvwxyz{|}~"
           "äöüÄÖÜß")


def muster(px=16, cw=10, ch=19, reason=14):
    s = raster.Font(MONO, px)
    aus = {}
    for c in CHARS:
        g = s.glyphe(ord(c))
        pk = set()
        for r in range(g.h):
            for k in range(g.w):
                if g.punkt(k, r) >= 128:
                    x, y = g.left + k, reason - g.top + r
                    if 0 <= x < cw and 0 <= y < ch:
                        pk.add((x, y))
        aus[c] = pk
    return aus


def ursprung(b, w, h):
    """Erste Spalte und Zeile mit Tinte."""
    x0 = y0 = None
    for y in range(h):
        for x in range(w):
            if b[x, y] == TINTE:
                y0 = y
                break
        if y0 is not None:
            break
    for x in range(w):
        for y in range(h):
            if b[x, y] == TINTE:
                x0 = x
                break
        if x0 is not None:
            break
    return x0, y0


def read_text(ppm, skala=2, cols=56, rows=20, cw=10, ch=19, reason=14,
         x0=None, y0=None):
    im = Image.open(ppm).convert("RGB")
    b = im.load()
    w, h = im.size
    if x0 is None or y0 is None:
        gx, gy = ursprung(b, w, h)
        if gx is None:
            return []
        # Die erste Tintenzeile ist die OBERKANTE der ersten Glyphe,
        # nicht die der Zelle. Fuer 'B'/'E' beginnt die Tinte bei
        # `grund - oben` = 14 - 12 = 2 Zellzeilen unter dem Zellanfang.
        x0 = gx if x0 is None else x0
        y0 = gy - 2 * skala if y0 is None else y0
    line_rows = []
    mus = muster(cw=cw, ch=ch, reason=reason)
    for r in range(rows):
        t = ""
        for c in range(cols):
            pk = set()
            for y in range(ch):
                for x in range(cw):
                    xx = x0 + c * cw * skala + x * skala
                    yy = y0 + r * ch * skala + y * skala
                    if 0 <= xx < w and 0 <= yy < h and b[xx, yy] == TINTE:
                        pk.add((x, y))
            if len(pk) < 3:
                t += " "
                continue
            bester, value = "?", -1e9
            for z, mp in mus.items():
                if not mp:
                    continue
                v = len(pk & mp) - 0.6 * len(pk ^ mp)
                if v > value:
                    value, bester = v, z
            t += bester
        line_rows.append(t.rstrip())
    return line_rows


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    d = {"skala": 2, "cols": 56, "rows": 20}
    for i, a in enumerate(argv):
        if a.startswith("--") and a[2:] in d and i + 1 < len(argv):
            d[a[2:]] = int(argv[i + 1])
    for i, z in enumerate(read_text(argv[1], **d)):
        if z.strip():
            print("%2d | %s" % (i, z))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
