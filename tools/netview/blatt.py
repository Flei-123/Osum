#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/netview/blatt.py -- die sieben Zeichen nebeneinander, 1:1 und gross.

Runde NETVIEW, Nachtrag. Das hier ist die EINZIGE Ausgabe dieser Runde,
die niemand nachrechnet: ein Blatt fuer einen Menschen, der sehen will,
wie die Zeichen aussehen. Alles, was gemessen wird, wird woanders
gemessen -- `icons.py pruefe` rechnet Kontrast und Schattenrisse,
`schau.py` haelt das Bild gegen den Schirm.

Es steht trotzdem hier und nicht in einem Notizbuch, weil die
ZIELGROSSE der Punkt ist: die obere Reihe jedes Blocks ist 1:1, also
genau so gross wie das Zeichen auf einer 28 Bildpunkte hohen
Taskleiste wirklich ist. Die vergroesserte Reihe darunter ist zum
Nachschauen, wie es gebaut ist, und niemals die Reihe, nach der
entschieden wird.

    blatt.py <ziel.png>
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


def bild(name, farben):
    palette, zeilen = symmod.lies(iconmod.zeichnung(name))
    h = len(zeilen)
    w = len(zeilen[0])
    punkte = []
    for z in zeilen:
        reihe = []
        for c in z:
            v = palette[c]
            if v is None:
                reihe.append(None)
            elif isinstance(v, tuple):
                reihe.append(farben[ROLLE_NAME[v[1]]])
            else:
                reihe.append(v)
        punkte.append(reihe)
    return w, h, punkte


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    try:
        from PIL import Image
    except ImportError:
        print("sheet: Pillow is not there")
        return 1
    namen = iconmod.ZUSTAENDE + iconmod.MERKMALE + iconmod.SYSTEM
    bloecke = []
    for schema in ("dark", "light"):
        farben = iconmod.SCHEMEN[schema]
        eins = []
        for n in namen:
            eins.append(bild(n, farben))
        breite = AIR + sum(max(w, w * BIG) + AIR for w, _, _ in eins)
        height_2 = AIR + 16 + AIR + 16 * BIG + AIR
        im = Image.new("RGB", (breite, height_2),
                       tuple(((farben["panel"] >> s) & 255) for s in (16, 8, 0)))
        x = AIR
        for w, h, punkte in eins:
            for r in range(h):
                for c in range(w):
                    v = punkte[r][c]
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
    breite = max(b.width for b in bloecke)
    height_2 = sum(b.height for b in bloecke)
    blatt = Image.new("RGB", (breite, height_2), (0, 0, 0))
    y = 0
    for b in bloecke:
        blatt.paste(b, (0, y))
        y += b.height
    blatt.save(argv[1])
    print("sheet: %s  %dx%d, %d characters, light and dark"
          % (argv[1], breite, height_2, len(namen)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
