#!/usr/bin/env python3
"""tools/blur/kante.py -- DEN BLUR AUS DEM BILD MESSEN, nicht ansehen.

DIE RICHTIGE FRAGE. Die Summe der Nachbarunterschiede taugt NICHT als
Mass: ein Schachbrett aus drei Farben hat je nach Zeile andere Kanten,
und eine getoente Flaeche hat kleinere Unterschiede, ohne deshalb
weichgezeichnet zu sein.

Was eine Weichzeichnung wirklich auszeichnet, ist die VERTEILUNG: eine
harte Kante ist EIN grosser Sprung zwischen zwei Nachbarn, eine weiche
ist eine LANGE REIHE kleiner Spruenge. Gemessen wird deshalb:

  GROSS   Nachbarpaare mit einem Sprung > 60 (harte Kanten)
  KLEIN   Nachbarpaare mit einem Sprung zwischen 4 und 60 (Uebergaenge)

Hinter dem Blur muss GROSS einbrechen und KLEIN steigen. Das ist eine
Aussage, die man nicht wegdiskutieren kann.
"""
import sys
from PIL import Image

def zeile(px, y, x0, x1):
    gross = klein = 0
    for x in range(x0, x1 - 1):
        a = px[x, y]; b = px[x + 1, y]
        d = abs(a[0]-b[0]) + abs(a[1]-b[1]) + abs(a[2]-b[2])
        if d > 60: gross += 1
        elif d >= 4: klein += 1
    return gross, klein

def main():
    im = Image.open(sys.argv[1]).convert('RGB')
    px = im.load()
    print(f"{'Zeile':>6}  {'was':<28} {'harte Kanten':>13} {'weiche Uebergaenge':>19}")
    proben = [
        (680, "blanker Grund",        600, 1270),
        (700, "blanker Grund",        600, 1270),
        (720, "HINTER der Leiste",    600, 1270),
        (735, "HINTER der Leiste",    600, 1270),
        (750, "HINTER der Leiste",    600, 1270),
        (500, "HINTER dem Menue",      90,  395),
        (600, "HINTER dem Menue",      90,  395),
        (500, "blanker Grund daneben",420,  725),
        (600, "blanker Grund daneben",420,  725),
    ]
    for y, was, x0, x1 in proben:
        g, k = zeile(px, y, x0, x1)
        print(f"{y:>6}  {was:<28} {g:>13} {k:>19}")

main()
