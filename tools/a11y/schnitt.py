#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/a11y/schnitt.py -- IST EINE BESCHRIFTUNG ABGESCHNITTEN?

    schnitt.py <bild.ppm> <x> <y> <w> <h>

Nicht "sieht gut aus", sondern eine Zahl: die Spalte der am WEITESTEN
RECHTS liegenden Tinte innerhalb des Rechtecks, gemessen als Abstand vom
rechten Rand.

Ein abgeschnittener Text hoert nicht auf, er BRICHT AB -- seine Tinte
laeuft bis an die letzte Spalte des Kastens und dort steht ein halber
Buchstabe.  Ein Text, der passt, hat rechts Luft.  Die Zusage lautet
deshalb: der Abstand ist mindestens 1.

"Tinte" ist alles, was sich von der haeufigsten Farbe des Rechtecks
(seiner Flaeche) unterscheidet -- so braucht dieses Programm das
Farbschema nicht zu kennen, und es funktioniert im hellen wie im
dunklen Modus und im hohen Kontrast.

Ausgabe: `rechts=<n> links=<n> tinte=<n>`, Rueckgabe 0.
"""
import sys
import os
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ppm import Bild


def main():
    if len(sys.argv) < 6:
        print(__doc__)
        return 2
    b = Bild(sys.argv[1])
    x, y, w, h = [int(v) for v in sys.argv[2:6]]
    zaehler = Counter()
    for r in range(h):
        for c in range(w):
            p = b.px(x + c, y + r)
            if p is not None:
                zaehler[p] += 1
    if not zaehler:
        print("rechts=-1 links=-1 tinte=0")
        return 0
    grund = zaehler.most_common(1)[0][0]
    links = w
    rechts = -1
    tinte = 0
    for r in range(h):
        for c in range(w):
            p = b.px(x + c, y + r)
            if p is not None and p != grund:
                tinte += 1
                if c < links:
                    links = c
                if c > rechts:
                    rechts = c
    if rechts < 0:
        print("rechts=-1 links=-1 tinte=0")
        return 0
    print("rechts=%d links=%d tinte=%d" % (w - 1 - rechts, links, tinte))
    return 0


sys.exit(main())
