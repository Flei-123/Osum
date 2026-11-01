#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    montage.py -- everything Bildschirmfotos in EIN Uebersichtsbild.
    montage.py <target.png> [columns]
"""
import os
import sys

from PIL import Image, ImageDraw


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "uebersicht.png"
    columns = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    d = "shots"
    names = sorted(f for f in os.listdir(d)
                   if f.endswith(".png") and not f.startswith("roi"))
    if not names:
        print("keine Bilder")
        return 1

    bw, bh = 384, 240          # Kachelgroesse
    beschriftung = 16
    rows = (len(names) + columns - 1) // columns
    ganz = Image.new("RGB", (columns * bw, rows * (bh + beschriftung)),
                     (24, 24, 28))
    zeichner = ImageDraw.Draw(ganz)

    for i, n in enumerate(names):
        try:
            im = Image.open(os.path.join(d, n)).convert("RGB")
        except Exception:
            continue
        im.thumbnail((bw - 4, bh - 4))
        x = (i % columns) * bw
        y = (i // columns) * (bh + beschriftung)
        ganz.paste(im, (x + 2, y + 2))
        brief = n[:-4]
        if len(brief) > 46:
            brief = brief[:45] + "…"
        zeichner.text((x + 3, y + bh + 2), brief, fill=(210, 210, 215))

    ganz.save(target)
    print("%s  %d Bilder, %dx%d" % (target, len(names), ganz.size[0], ganz.size[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
