#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/themestore/leistenvergleich.py -- DIE LEISTE VIERMAL UNTEREINANDER.

    leistenvergleich.py <ausgabe.png> [--hoehe=28] [--x0=0] [--x1=530]
                        [--vx0=300] [--vx1=1100] [--zoom=2]
                        <bild.png>=<Beschriftung> ...

Bild 12 der Runde GLAS war bis hierher ein von Hand zusammengesetzter
Ausschnitt: vier Streifen aus 04/05/06/07, uebereinandergelegt. Wer
wissen wollte, WELCHER Streifen welche Reglerstellung ist, musste die
README daneben aufschlagen -- und die Zahl, auf die es ankommt (die
Streuung des Untergrundes unter der Leiste), stand nur im Lauf.

Beides steht jetzt IM BILD, und die Zahl wird hier nicht abgetippt,
sondern GEMESSEN: `var` kommt aus `tools/themestore/glascheck.py`,
also aus derselben Rechnung, mit der die Abnahme das Milchglas
nachweist. Ein Bild, dessen Beschriftung aus einer zweiten Quelle
stammt, kann von der Messung abweichen, ohne dass es jemand merkt --
das ist genau der Fehler, den diese Runde an zwei anderen Stellen
schon bezahlt hat.

Der Ausschnitt ist der UNTERE Rand der Aufnahme (`--hoehe`, die Dicke
der Leiste) und die ersten `--x1` Bildpunkte davon: dort stehen
Startknopf, Fensterknopf und ein Stueck Untergrund nebeneinander.

GEMESSEN wird dagegen zwischen `--vx0` und `--vx1` -- dieselben 300
bis 1100, mit denen `glascheck.py var` in der Abnahme rechnet. Das ist
nicht derselbe Bereich wie der gezeigte, und das ist Absicht: in den
ersten dreihundert Bildpunkten stehen zwei Knoepfe und zwei Symbole,
deren Streuung mit der Durchsicht der Leiste nichts zu tun hat.
"""
import sys

from PIL import Image, ImageDraw, ImageFont

import glascheck

FONT = "assets/osum-sans.ttf"


def var_von(im, hoehe, x0, x1):
    """Die Streuung des Leistengrundes -- gerechnet von `glascheck`."""
    px = [im.getpixel(p) for p in glascheck.leiste(im, hoehe, x0, x1)]
    l = [glascheck.bright(p) for p in px]
    m = sum(l) / len(l)
    return int(sum((v - m) ** 2 for v in l) / len(l) * 100), len(set(px))


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    ziel = argv[1]
    hoehe, x0, x1, zoom = 28, 0, 530, 2
    vx0, vx1 = 300, 1100
    paare = []
    for a in argv[2:]:
        if a.startswith("--hoehe="):
            hoehe = int(a.split("=", 1)[1])
        elif a.startswith("--x0="):
            x0 = int(a.split("=", 1)[1])
        elif a.startswith("--x1="):
            x1 = int(a.split("=", 1)[1])
        elif a.startswith("--vx0="):
            vx0 = int(a.split("=", 1)[1])
        elif a.startswith("--vx1="):
            vx1 = int(a.split("=", 1)[1])
        elif a.startswith("--zoom="):
            zoom = int(a.split("=", 1)[1])
        else:
            file_2, _, text = a.partition("=")
            paare.append((file_2, text))
    try:
        font = ImageFont.truetype(FONT, 14)
    except OSError:
        font = ImageFont.load_default()
    width_2 = (x1 - x0) * zoom
    line = hoehe * zoom
    header = 20
    aus = Image.new("RGB", (width_2, (header + line + 8) * len(paare) + 4),
                    (255, 255, 255))
    mal = ImageDraw.Draw(aus)
    y = 4
    for file_2, text in paare:
        im = Image.open(file_2).convert("RGB")
        w, h = im.size
        var, farben = var_von(im, hoehe, vx0, vx1)
        streifen = im.crop((x0, h - hoehe, min(x1, w), h))
        streifen = streifen.resize((width_2, line), Image.NEAREST)
        mal.text((2, y), "%s   --   var %d, %d Farben" % (text, var, farben),
                 fill=(16, 16, 16), font=font)
        aus.paste(streifen, (0, y + header))
        mal.rectangle([0, y + header, width_2 - 1, y + header + line - 1],
                      outline=(160, 160, 168))
        y = y + header + line + 8
    aus.save(ziel)
    print("leistenvergleich: %s %dx%d aus %d Aufnahmen"
          % (ziel, aus.size[0], aus.size[1], len(paare)))
    return 0


if __name__ == "__main__":
    sys.path.insert(0, "tools/themestore")
    sys.exit(main(sys.argv))
