#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""bildpruef.py -- EIN BILD IN ZAHLEN, damit "ich habe hingesehen" belegbar ist.

    python3 bildpruef.py <bild.png> [x0 y0 x1 y1]

Justins Regel: "bitte immer selber visuell drueberschauen". Ein Modell
kann ein PNG nicht anschauen wie ein Mensch -- also wird es VERMESSEN,
und die Zahlen sind das, was in der Schlussmeldung steht:

  * die haeufigsten Farben (Schema erkannt? Hell oder dunkel?)
  * ganz leere Zeilen/Spalten (weisse Streifen, halbe Flaechen)
  * waagerechte Kanten (wo Flaechen anfangen und aufhoeren)
  * der Anteil Tinte je Achtelzeile (sitzt der Inhalt, wo er soll?)

Ein "Streifen" im Sinn von Justins Foto ist eine Folge von Zeilen, die
UEBER DIE GANZE FENSTERBREITE eine einzige Farbe haben, obwohl darueber
und darunter Inhalt steht. Genau danach wird gesucht.
"""
import sys
from collections import Counter

from PIL import Image


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    im = Image.open(sys.argv[1]).convert("RGB")
    W, H = im.size
    if len(sys.argv) >= 6:
        x0, y0, x1, y1 = (int(v) for v in sys.argv[2:6])
    else:
        x0, y0, x1, y1 = 0, 0, W, H
    print("Bild %s  %dx%d   Ausschnitt (%d,%d)-(%d,%d)"
          % (sys.argv[1], W, H, x0, y0, x1, y1))

    schritt = max(1, (x1 - x0) // 200)
    c = Counter(im.getpixel((x, y))
                for x in range(x0, x1, schritt)
                for y in range(y0, y1, max(1, (y1 - y0) // 200)))
    ges = sum(c.values())
    print("  Farben:")
    for f, n in c.most_common(5):
        print("    #%02x%02x%02x  %5.1f%%" % (f[0], f[1], f[2], 100.0 * n / ges))

    # einfarbige Zeilen -- der Streifentest
    einfarbig = []
    for y in range(y0, y1):
        row = [im.getpixel((x, y)) for x in range(x0, x1, schritt)]
        if len(set(row)) == 1:
            einfarbig.append((y, row[0]))
    if einfarbig:
        # zu Bloecken zusammenfassen
        bl = []
        s = einfarbig[0][0]
        p = einfarbig[0][0]
        f = einfarbig[0][1]
        for y, fa in einfarbig[1:]:
            if y == p + 1 and fa == f:
                p = y
            else:
                bl.append((s, p, f))
                s, p, f = y, y, fa
        bl.append((s, p, f))
        gross = [b for b in bl if b[1] - b[0] >= 8]
        print("  einfarbige Zeilenbloecke (>=8 hoch): %d" % len(gross))
        for a, b, fa in gross[:8]:
            print("    y=%d..%d (%d hoch)  #%02x%02x%02x"
                  % (a, b, b - a + 1, fa[0], fa[1], fa[2]))
    else:
        print("  keine einfarbige Zeile -- ueberall Inhalt")

    # Tinte je Achtel
    print("  Tinte je Achtelzeile (Anteil Punkte != haeufigste Farbe):")
    grund = c.most_common(1)[0][0]
    hoch = (y1 - y0) // 8
    for k in range(8):
        ya, yb = y0 + k * hoch, y0 + (k + 1) * hoch
        n = t = 0
        for y in range(ya, yb, max(1, hoch // 12)):
            for x in range(x0, x1, schritt):
                t += 1
                p = im.getpixel((x, y))
                if abs(p[0] - grund[0]) + abs(p[1] - grund[1]) \
                        + abs(p[2] - grund[2]) > 40:
                    n += 1
        print("    y=%4d..%4d  %5.1f%%" % (ya, yb, 100.0 * n / max(1, t)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
