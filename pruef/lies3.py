#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    read3.py -- den Text im Terminalfenster read_all.
    python3 read3.py <ppm> [--rows N --cols N]
"""
import json
import os
import sys

from PIL import Image

HIER = os.path.dirname(os.path.abspath(__file__))
TINTE = (0, 255, 102)
FONT = os.path.join(HIER, "schrift.json")
CW, CH, SKALA = 8, 16, 2


def gitter(ppm):
    """Ursprung und Zellenraster aus dem Bild selbst bestimmen."""
    im = Image.open(ppm).convert("RGB")
    b = im.load()
    w, h = im.size
    xs = sorted({x for x in range(w)
                 if any(b[x, y] == TINTE for y in range(h))})
    ys = sorted({y for y in range(h)
                 if any(b[x, y] == TINTE for x in range(w))})
    if not xs or not ys:
        return None
    # Der Ursprung der Zelle liegt links/oben von der ersten Tinte.
    # Die Spalten stehen im Abstand CW*SKALA; also den Rest wegrechnen.
    x0 = xs[0] - (xs[0] % (CW * SKALA))
    # Die Zeilen: der erste Block beginnt bei ys[0]; die Grundlinie der
    # Schrift sitzt nicht am Zellanfang, darum wird die Zeilenhoehe aus
    # den Abstaenden der Bloecke geholt und der Anfang zurueckgerechnet.
    y0 = ys[0]
    bloecke = []
    a = p = ys[0]
    for y in ys[1:]:
        if y > p + 1:
            bloecke.append((a, p))
            a = y
        p = y
    bloecke.append((a, p))
    if len(bloecke) >= 2:
        schritte = [bloecke[i + 1][0] - bloecke[i][0]
                    for i in range(len(bloecke) - 1)]
        eng = [s for s in schritte if s % (CH * SKALA) == 0]
        if eng:
            y0 = bloecke[0][0] - (bloecke[0][0] % (CH * SKALA))
    return im, b, w, h, x0, y0


def zellen(b, w, h, x0, y0, cols, rows):
    for r in range(rows):
        for c in range(cols):
            pk = set()
            for y in range(CH):
                for x in range(CW):
                    xx = x0 + (c * CW + x) * SKALA
                    yy = y0 + (r * CH + y) * SKALA
                    if 0 <= xx < w and 0 <= yy < h and b[xx, yy] == TINTE:
                        pk.add((x, y))
            yield r, c, pk


def loader():
    if os.path.exists(FONT):
        d = json.load(open(FONT))
        return {k: set(tuple(p) for p in v) for k, v in d.items()}
    return {}


def lerne(ppm, text, cols=70, rows=24):
    """Aus einem Foto mit BEKANNTEM Text die Muster ziehen."""
    g = gitter(ppm)
    if not g:
        print("keine Tinte im Bild")
        return 1
    im, b, w, h, x0, y0 = g
    mus = loader()
    line_rows = text.split("\n")
    for r, c, pk in zellen(b, w, h, x0, y0, cols, rows):
        if r >= len(line_rows) or c >= len(line_rows[r]):
            continue
        z = line_rows[r][c]
        if z == " " or not pk:
            continue
        mus.setdefault(z, pk)
    json.dump({k: sorted(list(v)) for k, v in mus.items()},
              open(FONT, "w"))
    print("gelernt: %d Zeichen -> %s" % (len(mus), FONT))
    return 0


def read_text(ppm, cols=70, rows=24):
    g = gitter(ppm)
    if not g:
        return []
    im, b, w, h, x0, y0 = g
    mus = loader()
    aus = [""] * rows
    for r, c, pk in zellen(b, w, h, x0, y0, cols, rows):
        if len(pk) < 2:
            aus[r] += " "
            continue
        if not mus:
            aus[r] += "#"
            continue
        bester, value = "?", -1e9
        for z, mp in mus.items():
            v = len(pk & mp) - 0.7 * len(pk ^ mp)
            if v > value:
                value, bester = v, z
        aus[r] += bester if value > -6 else "?"
    return [z.rstrip() for z in aus]


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    ppm = argv[1]
    cols = rows = None
    for i, a in enumerate(argv):
        if a == "--cols":
            cols = int(argv[i + 1])
        if a == "--rows":
            rows = int(argv[i + 1])
        if a == "--lerne":
            return lerne(ppm, argv[i + 1], cols or 70, rows or 24)
    for i, z in enumerate(read_text(ppm, cols or 70, rows or 24)):
        if z.strip():
            print("%2d | %s" % (i, z))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
