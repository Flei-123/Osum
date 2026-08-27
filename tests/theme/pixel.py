#!/usr/bin/env python3
"""tests/theme/pixel.py -- was in einem Bildschirmfoto WIRKLICH steht.

    pixel.py <bild.ppm>                 die haeufigste Farbe
    pixel.py <bild.ppm> --top 5         die fuenf haeufigsten mit Anteil
    pixel.py <bild.ppm> --has RRGGBB    Beendigungscode 0, wenn es sie gibt
    pixel.py <bild.ppm> --at X Y        die Farbe an genau dieser Stelle

Ein PPM (P6) selbst zu lesen ist zwanzig Zeilen und spart eine
Abhaengigkeit; der Rest des Baums liest seine Bilder in `tools/gfx/`
genauso.

WOZU DAS GEBRAUCHT WIRD: die Zusage der Runde ist nicht "es sieht
anders aus", sondern "die Farben auf dem Schirm SIND die aufgeloesten
Marken". Das laesst sich nur im Bild nachrechnen, und ein Auge, das
zwei Blautoene vergleicht, rechnet nicht nach.
"""
import sys
from collections import Counter


def read_ppm(path):
    with open(path, "rb") as f:
        data = f.read()
    if not data.startswith(b"P6"):
        raise SystemExit("pixel.py: %s ist kein P6-PPM" % path)
    # Kopf: P6, Breite, Hoehe, Maximalwert -- Kommentare beginnen mit '#'
    fields = []
    i = 2
    while len(fields) < 3:
        while i < len(data) and data[i:i + 1].isspace():
            i += 1
        if data[i:i + 1] == b"#":
            while i < len(data) and data[i:i + 1] != b"\n":
                i += 1
            continue
        j = i
        while j < len(data) and not data[j:j + 1].isspace():
            j += 1
        fields.append(int(data[i:j]))
        i = j
    i += 1
    w, h, _mx = fields
    return w, h, data[i:i + w * h * 3]


def census(px):
    c = Counter()
    for k in range(0, len(px), 3):
        c[(px[k], px[k + 1], px[k + 2])] += 1
    return c


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    w, h, px = read_ppm(sys.argv[1])
    total = w * h
    c = census(px)
    args = sys.argv[2:]
    if args and args[0] == "--has":
        want = args[1].lower().lstrip("#")
        col = (int(want[0:2], 16), int(want[2:4], 16), int(want[4:6], 16))
        n = c.get(col, 0)
        print("%06x %d" % (int(want, 16), n))
        return 0 if n > 0 else 1
    if args and args[0] == "--at":
        x, y = int(args[1]), int(args[2])
        k = (y * w + x) * 3
        print("%02x%02x%02x" % (px[k], px[k + 1], px[k + 2]))
        return 0
    top = 1
    if args and args[0] == "--top":
        top = int(args[1])
    out = []
    for col, n in c.most_common(top):
        out.append("%02x%02x%02x:%.1f%%"
                   % (col[0], col[1], col[2], 100.0 * n / total))
    print(" ".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
