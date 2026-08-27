#!/usr/bin/env python3
"""tools/k15/count.py -- Bildpunkte einer Farbe in einem Rechteck zaehlen.

    count.py <ppm> <x> <y> <w> <h> <r> <g> <b>

`checkshot.py flaeche` verlangt, dass ALLE Bildpunkte des Rechtecks die
Farbe haben; hier geht es um das Gegenteil: WIE VIELE sind es?  Das ist
die Form, in der sich ein Haken in einem Kaestchen messen laesst -- er
ist kein volles Rechteck, er ist ein Strich, und die Zusage lautet
"nach dem Klick sind es mehr als zwoelf, vorher genau null".

Ausgabe: eine Zahl.
"""
import sys


def lade(pfad):
    d = open(pfad, "rb").read()
    teile = []
    i = 0
    while len(teile) < 4:
        while d[i:i + 1] in b" \t\r\n":
            i += 1
        if d[i:i + 1] == b"#":
            while d[i:i + 1] not in b"\r\n":
                i += 1
            continue
        j = i
        while d[j:j + 1] not in b" \t\r\n":
            j += 1
        teile.append(d[i:j])
        i = j
    i += 1
    if teile[0] != b"P6":
        raise SystemExit("kein P6-PPM: %s" % teile[0])
    return int(teile[1]), int(teile[2]), d[i:]


def main():
    if len(sys.argv) < 9:
        print(__doc__)
        return 2
    ppm = sys.argv[1]
    x0, y0, w, h = (int(v) for v in sys.argv[2:6])
    ziel = tuple(int(v) for v in sys.argv[6:9])
    W, H, px = lade(ppm)
    n = 0
    for y in range(y0, min(y0 + h, H)):
        for x in range(x0, min(x0 + w, W)):
            o = (y * W + x) * 3
            if (px[o], px[o + 1], px[o + 2]) == ziel:
                n += 1
    print(n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
