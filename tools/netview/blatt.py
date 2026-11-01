#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    blatt.py <target.png>
"""

import os
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HIER), "k15"))
sys.path.insert(0, HIER)
import icon as symmod  # noqa: E402
import icons as iconmod  # noqa: E402

ROLLE_NAME = {v: k for k, v in symmod.ROLLEN.items()}
BIG = 6
AIR = 6


def image(name, farben):
    palette, rows = symmod.read_2(iconmod.zeichnung(name))
    h = len(rows)
    w = len(rows[0])
    points = []
    for z in rows:
        reihe = []
        for c in z:
            v = palette[c]
            if v is None:
                reihe.append(None)
            elif isinstance(v, tuple):
                reihe.append(farben[ROLLE_NAME[v[1]]])
            else:
                reihe.append(v)
        points.append(reihe)
    return w, h, points


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    try:
        from PIL import Image
    except ImportError:
        print("sheet: Pillow is not there")
        return 1
    names = iconmod.ZUSTAENDE + iconmod.MERKMALE + iconmod.SYSTEM
    bloecke = []
    for schema in ("dark", "light"):
        farben = iconmod.SCHEMEN[schema]
        eins = []
        for n in names:
            eins.append(image(n, farben))
        width_2 = AIR + sum(max(w, w * BIG) + AIR for w, _, _ in eins)
        height_2 = AIR + 16 + AIR + 16 * BIG + AIR
        im = Image.new("RGB", (width_2, height_2),
                       tuple(((farben["panel"] >> s) & 255) for s in (16, 8, 0)))
        x = AIR
        for w, h, points in eins:
            for r in range(h):
                for c in range(w):
                    v = points[r][c]
                    if v is None:
                        continue
                    rgb = ((v >> 16) & 255, (v >> 8) & 255, v & 255)
                    im.putpixel((x + c, AIR + r), rgb)
                    for dy in range(BIG):
                        for dx in range(BIG):
                            im.putpixel((x + c * BIG + dx,
                                         AIR + 16 + AIR + r * BIG + dy),
                                        rgb)
            x += max(w, w * BIG) + AIR
        bloecke.append(im)
    width_2 = max(b.width for b in bloecke)
    height_2 = sum(b.height for b in bloecke)
    blatt = Image.new("RGB", (width_2, height_2), (0, 0, 0))
    y = 0
    for b in bloecke:
        blatt.paste(b, (0, y))
        y += b.height
    blatt.save(argv[1])
    print("sheet: %s  %dx%d, %d characters, light and dark"
          % (argv[1], width_2, height_2, len(names)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
