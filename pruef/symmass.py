#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""symmass.py -- WIE GROSS EIN SYMBOL WIRKLICH AUF DEM SCHIRM IST.

    python3 symmass.py <bild.png> <x> <y> <w> <h>

Misst in einem Ausschnitt die AUSDEHNUNG DER FARBIGEN TINTE: alles,
was sich vom haeufigsten Farbton (dem Hintergrund des Ausschnitts)
unterscheidet. Ausgegeben wird die Hoehe und Breite dieser Flaeche.

WOZU. Die serielle Leitung meldet `taskbar: sym ... w=16`, und diese
16 sind die Groesse der BILDDATEI -- nicht die Zahl der Bildpunkte,
die am Ende auf dem Schirm stehen. Nach der Vergroesserung in
`wlibc.icon_draw` sind beide Zahlen verschieden, und nur die zweite
beantwortet Justins Satz "die Symbole sind winzig". Sie steht in
keinem Log, sie steht nur im Bild.
"""
import sys
from collections import Counter

try:
    from PIL import Image
except ImportError:
    print("PIL fehlt", file=sys.stderr)
    sys.exit(2)


def main():
    if len(sys.argv) < 6:
        print(__doc__)
        return 2
    bild = sys.argv[1]
    x, y, w, h = (int(v) for v in sys.argv[2:6])
    im = Image.open(bild).convert("RGB")
    aus = im.crop((x, y, x + w, y + h))
    px = list(aus.getdata())
    grund = Counter(px).most_common(1)[0][0]

    minx, miny, maxx, maxy = w, h, -1, -1
    n = 0
    for i, p in enumerate(px):
        # Abstand vom Grundton, grosszuegig: ein Symbol darf einen
        # weichen Rand haben, ohne dass er als Hintergrund zaehlt.
        d = abs(p[0] - grund[0]) + abs(p[1] - grund[1]) + abs(p[2] - grund[2])
        if d > 40:
            cx, cy = i % w, i // w
            n += 1
            minx = min(minx, cx)
            maxx = max(maxx, cx)
            miny = min(miny, cy)
            maxy = max(maxy, cy)
    if maxx < 0:
        print("keine Tinte im Ausschnitt (Grundton %s)" % (grund,))
        return 1
    print("grund=%s tinte=%d punkte" % (grund, n))
    print("kasten x=%d..%d (%d breit)  y=%d..%d (%d hoch)"
          % (x + minx, x + maxx, maxx - minx + 1,
             y + miny, y + maxy, maxy - miny + 1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
