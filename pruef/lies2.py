#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""lies2.py -- den Text im Terminalfenster LESEN, auch bei 2x-Bild.

    python3 lies2.py <ppm> [--x0 N --y0 N --skala N --cols N --rows N]

WAS DIE VORLAEUFER FALSCH GEMACHT HABEN, und warum das wichtig ist:

1. NUR DIE TINTENFARBE ZAEHLT. Das Terminal malt gruen (0,255,102) auf
   schwarz. Eine Helligkeitsschwelle nimmt den hellblauen Fensterrahmen
   und die graue Leiste mit, und dann steht in jeder Randzelle ein
   Zeichen, das dort nicht ist.

2. DAS BILD IST ZWEIFACH VERGROESSERT. Gemessen: von 19 063 waagrechten
   Nachbarpaaren waren 19 031 gleich -- jeder Bildpunkt steht doppelt.
   Der Kern meldet `cell=10x19`, auf dem Schirm ist die Zelle also
   20x38. Wer mit 10x19 rastert, vergleicht ein 'o' mit dem linken
   oberen Viertel eines 'o' und liest Kraut und Rueben. (Der Grund ist
   die Skalierung der Oberflaeche, nicht `fbres`: der Mitschnitt sagt
   `skala x1` fuer den Rahmenpuffer.)

3. DER URSPRUNG WIRD GEMESSEN, NICHT GERECHNET. Statt aus Fensterlage,
   Rand und Titelhoehe zu addieren (drei Zahlen, drei Gelegenheiten,
   sich zu irren), wird die erste gruene Zeile und Spalte gesucht --
   dort faengt die erste Zelle mit Tinte an.
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
ZEICHEN = (" !\"#$%&'()*+,-./0123456789:;<=>?@"
           "ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`"
           "abcdefghijklmnopqrstuvwxyz{|}~"
           "äöüÄÖÜß")


def muster(px=16, cw=10, ch=19, grund=14):
    s = raster.Schrift(MONO, px)
    aus = {}
    for c in ZEICHEN:
        g = s.glyphe(ord(c))
        pk = set()
        for r in range(g.h):
            for k in range(g.w):
                if g.punkt(k, r) >= 128:
                    x, y = g.links + k, grund - g.oben + r
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


def lies(ppm, skala=2, cols=56, rows=20, cw=10, ch=19, grund=14,
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
    zeilen = []
    mus = muster(cw=cw, ch=ch, grund=grund)
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
            bester, wert = "?", -1e9
            for z, mp in mus.items():
                if not mp:
                    continue
                v = len(pk & mp) - 0.6 * len(pk ^ mp)
                if v > wert:
                    wert, bester = v, z
            t += bester
        zeilen.append(t.rstrip())
    return zeilen


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    d = {"skala": 2, "cols": 56, "rows": 20}
    for i, a in enumerate(argv):
        if a.startswith("--") and a[2:] in d and i + 1 < len(argv):
            d[a[2:]] = int(argv[i + 1])
    for i, z in enumerate(lies(argv[1], **d)):
        if z.strip():
            print("%2d | %s" % (i, z))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
