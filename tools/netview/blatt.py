#!/usr/bin/env python3
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
import symbol as symmod  # noqa: E402
import icons as iconmod  # noqa: E402

ROLLE_NAME = {v: k for k, v in symmod.ROLLEN.items()}
GROSS = 6
LUFT = 6


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
        print("blatt: Pillow ist nicht da")
        return 1
    namen = iconmod.ZUSTAENDE + iconmod.MERKMALE
    bloecke = []
    for schema in ("dark", "light"):
        farben = iconmod.SCHEMEN[schema]
        eins = []
        for n in namen:
            eins.append(bild(n, farben))
        breite = LUFT + sum(max(w, w * GROSS) + LUFT for w, _, _ in eins)
        hoehe = LUFT + 16 + LUFT + 16 * GROSS + LUFT
        im = Image.new("RGB", (breite, hoehe),
                       tuple(((farben["panel"] >> s) & 255) for s in (16, 8, 0)))
        x = LUFT
        for w, h, punkte in eins:
            for r in range(h):
                for c in range(w):
                    v = punkte[r][c]
                    if v is None:
                        continue
                    rgb = ((v >> 16) & 255, (v >> 8) & 255, v & 255)
                    im.putpixel((x + c, LUFT + r), rgb)
                    for dy in range(GROSS):
                        for dx in range(GROSS):
                            im.putpixel((x + c * GROSS + dx,
                                         LUFT + 16 + LUFT + r * GROSS + dy),
                                        rgb)
            x += max(w, w * GROSS) + LUFT
        bloecke.append(im)
    breite = max(b.width for b in bloecke)
    hoehe = sum(b.height for b in bloecke)
    blatt = Image.new("RGB", (breite, hoehe), (0, 0, 0))
    y = 0
    for b in bloecke:
        blatt.paste(b, (0, y))
        y += b.height
    blatt.save(argv[1])
    print("blatt: %s  %dx%d, %d Zeichen, hell und dunkel"
          % (argv[1], breite, hoehe, len(namen)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
