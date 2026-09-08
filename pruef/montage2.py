#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""montage.py -- alle Bildschirmfotos in EIN Uebersichtsbild.

    montage.py <ziel.png> [spalten]

ImageMagick liegt auf diesem Rechner nicht, PIL schon -- also wird die
Montage damit gebaut. Jedes Foto bekommt seinen DATEINAMEN unter das
Bild geschrieben, sonst ist eine Uebersicht aus 30 dunklen
Schreibtischen nicht zuzuordnen.
"""
import os
import sys

from PIL import Image, ImageDraw


def main():
    ziel = sys.argv[1] if len(sys.argv) > 1 else "uebersicht.png"
    spalten = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    # RUNDE TUERSCHLOSS: die Fotos liegen je Lauf in einem eigenen
    # Verzeichnis (shots/dk1280, shots/dk1920), damit die beiden
    # Aufloesungen nicht durcheinandergeraten. Ohne Angabe: alle.
    d = sys.argv[3] if len(sys.argv) > 3 else "shots"
    namen = []
    for wurzel, _, dateien in os.walk(d):
        for f in sorted(dateien):
            if f.endswith(".png") and not f.startswith("roi"):
                namen.append(os.path.relpath(os.path.join(wurzel, f), d))
    namen.sort()
    if not namen:
        print("keine Bilder")
        return 1

    bw, bh = 384, 240          # Kachelgroesse
    beschriftung = 16
    zeilen = (len(namen) + spalten - 1) // spalten
    ganz = Image.new("RGB", (spalten * bw, zeilen * (bh + beschriftung)),
                     (24, 24, 28))
    zeichner = ImageDraw.Draw(ganz)

    for i, n in enumerate(namen):
        try:
            im = Image.open(os.path.join(d, n)).convert("RGB")
        except Exception:
            continue
        im.thumbnail((bw - 4, bh - 4))
        x = (i % spalten) * bw
        y = (i // spalten) * (bh + beschriftung)
        ganz.paste(im, (x + 2, y + 2))
        kurz = n[:-4]
        if len(kurz) > 46:
            kurz = kurz[:45] + "…"
        zeichner.text((x + 3, y + bh + 2), kurz, fill=(210, 210, 215))

    ganz.save(ziel)
    print("%s  %d Bilder, %dx%d" % (ziel, len(namen), ganz.size[0], ganz.size[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
