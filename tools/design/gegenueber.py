#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    gegenueber.py <vorher-directory> <nachher-directory> <target>
"""
import os
import sys

from PIL import Image, ImageDraw

NAMES = [
    ("01-schreibtisch", "Schreibtisch"),
    ("07-taskleiste", "Taskleiste"),
    ("02-startmenue", "Startmenue"),
    ("03-explorer", "Dateimanager"),
    ("04-dialog", "Dialog"),
    ("05-kontrollzentrum", "Kontrollzentrum"),
    ("06-einstellungen", "Einstellungen"),
]
RAND = 12
HEADER = 26


def load_2(d, name):
    for e in (".png", ".ppm"):
        p = os.path.join(d, name + e)
        if os.path.exists(p):
            return Image.open(p).convert("RGB")
    return None


def paar(a, b, title, target):
    if a is None or b is None:
        return False
    w = a.size[0] + b.size[0] + 3 * RAND
    h = max(a.size[1], b.size[1]) + 2 * RAND + HEADER
    im = Image.new("RGB", (w, h), (24, 24, 27))
    d = ImageDraw.Draw(im)
    im.paste(a, (RAND, RAND + HEADER))
    im.paste(b, (2 * RAND + a.size[0], RAND + HEADER))
    d.text((RAND, 8), "%s -- VORHER (classic)" % title, fill=(244, 244, 245))
    d.text((2 * RAND + a.size[0], 8), "%s -- NACHHER (osum)" % title,
           fill=(134, 239, 172))
    im.save(target)
    return True


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    v, n, z = sys.argv[1:4]
    os.makedirs(z, exist_ok=True)
    gemacht = 0
    for name, title in NAMES:
        a, b = load_2(v, name), load_2(n, name)
        if paar(a, b, title, os.path.join(z, "gg-%s.png" % name)):
            print("gegenueber %s" % name)
            gemacht += 1
    print("%d Paare" % gemacht)
    return 0


if __name__ == "__main__":
    sys.exit(main())
