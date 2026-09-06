#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/certus/farbe.py -- wie oft eine BESTIMMTE Farbe im Bild steht.

Der Unterschied zwischen "es ist Tinte da" und "die Seite ist da": eine
Seite verlangt `background:#0033aa` auf 300 x 80 Bildpunkten, und dann
muessen 24000 Bildpunkte genau diese Farbe haben. Ein Browser, der
irgendetwas malt, besteht die Tintenzaehlung und diese hier nicht.

    farbe.py <bild.ppm> <rrggbb>
"""
import sys


def main():
    b = open(sys.argv[1], "rb").read()
    want = bytes.fromhex(sys.argv[2])
    parts = []
    i = 2
    while len(parts) < 3:
        while i < len(b) and b[i:i + 1].isspace():
            i += 1
        j = i
        while j < len(b) and not b[j:j + 1].isspace():
            j += 1
        parts.append(int(b[i:j]))
        i = j
    i += 1
    w, h, _ = parts
    px = b[i:i + w * h * 3]
    n = 0
    for k in range(0, len(px) - 2, 3):
        if px[k:k + 3] == want:
            n += 1
    print(n)


if __name__ == "__main__":
    main()
