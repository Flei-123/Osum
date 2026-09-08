#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""lies.py -- den INHALT des Terminalfensters aus einem Foto LESEN.

    python3 lies.py <ppm> [--x0 N --y0 N --cols N --rows N --cw N --ch N]

WARUM ES DAS BRAUCHT, und warum `suchtext.py` hier nicht reicht.

`suchtext.py` beantwortet: "steht DIESER Text irgendwo im Bild?" -- man
muss den Text also schon kennen. Wenn eine Shell etwas antwortet, das
man NICHT erwartet hat (eine Fehlermeldung, ein anderer Pfad, ein
Tippfehler), raet man Woerter und bekommt "nicht gefunden" zurueck, was
alles und nichts heisst. Genau daran hing in dieser Runde die Frage,
warum `shutdown` nicht abschaltet.

Hier wird umgekehrt vorgegangen. Beim Terminal des Kerns steht alles
fest, was man sonst schaetzen muesste:

    wm: term win=0 cols=56 rows=20 cell=10x19

Also: jedes druckbare Zeichen EINMAL mit derselben Schrift rastern, die
das System benutzt (assets/osum-mono.ttf), und dann jede Zelle mit
allen Mustern vergleichen. Das ist kein allgemeines Texterkennen -- es
ist ein Vergleich in einem Raster, in dem Lage, Zellgroesse und Schrift
bekannt sind. Deshalb ist es zuverlaessig und deshalb steht es hier und
nicht in tools/.
"""
import os
import sys

from PIL import Image

HIER = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HIER, ".."))
sys.path.insert(0, os.path.join(REPO, "tools", "ttf"))
import raster  # noqa: E402

MONO = os.path.join(REPO, "assets", "osum-mono.ttf")
ZEICHEN = (" !\"#$%&'()*+,-./0123456789:;<=>?@"
           "ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`"
           "abcdefghijklmnopqrstuvwxyz{|}~"
           "äöüÄÖÜß")


def muster(px, cw, ch, grund):
    """Je Zeichen sein Bild in der Zelle: Menge der gesetzten Punkte."""
    s = raster.Schrift(MONO, px)
    aus = {}
    for c in ZEICHEN:
        g = s.glyphe(ord(c))
        pk = set()
        if g.w and g.h:
            for r in range(g.h):
                for k in range(g.w):
                    if g.punkt(k, r) >= 128:
                        x = g.links + k
                        y = grund - g.oben + r
                        if 0 <= x < cw and 0 <= y < ch:
                            pk.add((x, y))
        aus[c] = pk
    return aus


def zelle_punkte(im, x0, y0, cw, ch, tinte=(0, 255, 102)):
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


def lies(ppm, x0=26, y0=62, cols=56, rows=20, cw=10, ch=19, px=16,
         grund=14):
    im = Image.open(ppm).convert("RGB")
    mus = muster(px, cw, ch, grund)
    zeilen = []
    for r in range(rows):
        text = ""
        for c in range(cols):
            pk = zelle_punkte(im, x0 + c * cw, y0 + r * ch, cw, ch)
            if len(pk) < 3:
                text += " "
                continue
            bester, wert = " ", -1.0
            for zeichen, mp in mus.items():
                if not mp and not pk:
                    continue
                if not mp:
                    continue
                treffer = len(pk & mp)
                fehl = len(pk ^ mp)
                w = treffer - 0.55 * fehl
                if w > wert:
                    wert, bester = w, zeichen
            text += bester
        zeilen.append(text.rstrip())
    return zeilen


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    d = {"x0": 26, "y0": 62, "cols": 56, "rows": 20, "cw": 10, "ch": 19,
         "px": 16, "grund": 14}
    for i, a in enumerate(argv):
        if a.startswith("--") and a[2:] in d and i + 1 < len(argv):
            d[a[2:]] = int(argv[i + 1])
    for i, z in enumerate(lies(argv[1], **d)):
        if z.strip():
            print("%2d | %s" % (i, z))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
