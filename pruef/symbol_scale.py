#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    symbol_scale.py -- WIE large EIN SYMBOL WIRKLICH AUF DEM SCREEN IST.
    python3 symbol_scale.py <image.png> <x> <y> <w> <h>
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
    image = sys.argv[1]
    x, y, w, h = (int(v) for v in sys.argv[2:6])
    im = Image.open(image).convert("RGB")
    aus = im.crop((x, y, x + w, y + h))
    px = list(aus.getdata())
    reason = Counter(px).most_common(1)[0][0]

    minx, miny, maxx, maxy = w, h, -1, -1
    n = 0
    for i, p in enumerate(px):
        # Abstand vom Grundton, grosszuegig: ein Symbol darf einen
        # weichen Rand haben, ohne dass er als Hintergrund zaehlt.
        d = abs(p[0] - reason[0]) + abs(p[1] - reason[1]) + abs(p[2] - reason[2])
        if d > 40:
            cx, cy = i % w, i // w
            n += 1
            minx = min(minx, cx)
            maxx = max(maxx, cx)
            miny = min(miny, cy)
            maxy = max(maxy, cy)
    if maxx < 0:
        print("keine Tinte im Ausschnitt (Grundton %s)" % (reason,))
        return 1
    print("grund=%s tinte=%d punkte" % (reason, n))
    print("kasten x=%d..%d (%d breit)  y=%d..%d (%d hoch)"
          % (x + minx, x + maxx, maxx - minx + 1,
             y + miny, y + maxy, maxy - miny + 1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
