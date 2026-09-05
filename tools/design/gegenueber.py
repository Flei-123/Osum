#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/design/gegenueber.py -- VORHER UND NACHHER IN EINEM BILD.

    gegenueber.py <vorher-verzeichnis> <nachher-verzeichnis> <ziel>

Zwei Aufnahmen derselben Ansicht nebeneinander, mit Beschriftung, und
eine Uebersicht ueber alle sieben.  Ein Vergleich, bei dem man zwischen
zwei Dateien hin- und herklicken muss, ist keiner: die Unterschiede, um
die es hier geht -- vier Bildpunkte Abstand, ein Radius, eine
Zeilenhoehe --, sieht man nur direkt nebeneinander.
"""
import os
import sys

from PIL import Image, ImageDraw

NAMEN = [
    ("01-schreibtisch", "Schreibtisch"),
    ("07-taskleiste", "Taskleiste"),
    ("02-startmenue", "Startmenue"),
    ("03-explorer", "Dateimanager"),
    ("04-dialog", "Dialog"),
    ("05-kontrollzentrum", "Kontrollzentrum"),
    ("06-einstellungen", "Einstellungen"),
]
RAND = 12
KOPF = 26


def lade(d, name):
    for e in (".png", ".ppm"):
        p = os.path.join(d, name + e)
        if os.path.exists(p):
            return Image.open(p).convert("RGB")
    return None


def paar(a, b, titel, ziel):
    if a is None or b is None:
        return False
    w = a.size[0] + b.size[0] + 3 * RAND
    h = max(a.size[1], b.size[1]) + 2 * RAND + KOPF
    im = Image.new("RGB", (w, h), (24, 24, 27))
    d = ImageDraw.Draw(im)
    im.paste(a, (RAND, RAND + KOPF))
    im.paste(b, (2 * RAND + a.size[0], RAND + KOPF))
    d.text((RAND, 8), "%s -- VORHER (classic)" % titel, fill=(244, 244, 245))
    d.text((2 * RAND + a.size[0], 8), "%s -- NACHHER (osum)" % titel,
           fill=(134, 239, 172))
    im.save(ziel)
    return True


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    v, n, z = sys.argv[1:4]
    os.makedirs(z, exist_ok=True)
    gemacht = 0
    for name, titel in NAMEN:
        a, b = lade(v, name), lade(n, name)
        if paar(a, b, titel, os.path.join(z, "gg-%s.png" % name)):
            print("gegenueber %s" % name)
            gemacht += 1
    print("%d Paare" % gemacht)
    return 0


if __name__ == "__main__":
    sys.exit(main())
