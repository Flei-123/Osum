#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/themestore/streifen.py -- DER VERGLEICHSSTREIFEN DER LEISTE.

    streifen.py <ziel.png> <bild.png>=<beschriftung> [...]

Aus jeder Aufnahme wird der Streifen der Taskleiste ausgeschnitten,
zweifach vergroessert und mit den anderen untereinandergelegt -- das ist
Bild 12 der Runde GLAS.

WARUM DAS EIN WERKZEUG IST UND KEIN HANDGRIFF.

Bild 12 war bis hierher von Hand zusammengesetzt, und man sah ihm das
an: vier graue Streifen ohne ein Wort daran.  Wer wissen wollte, welcher
Streifen 70 und welcher 40 Prozent ist, musste das README danebenlegen
-- ein Bildvergleich, der eine Textdatei braucht, vergleicht nichts.

Jede Reihe traegt deshalb IM BILD ihre Beschriftung und die Zahl, die
sie belegt: die Streuung `var` des Streifens, gerechnet mit genau den
Funktionen aus `tools/themestore/glascheck.py`, mit denen der
Abnahmelauf sie misst.  Eine zweite Rechnung daneben waere eine zweite
Wahrheit; hier wird dieselbe importiert.

`var` ist die Zahl, an der Milchglas haengt: eine deckende Leiste hat
0 (eine Farbe), eine durchscheinende ueber einem Schachbrett ein paar
tausend (zwei Farben), und der Weichzeichner muss sie messbar SENKEN,
ohne sie auf 0 zu druecken.  Steht sie an der Reihe, traegt der
Bildvergleich ohne Mitschnitt.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glascheck                                     # noqa: E402

HOEHE = 28          # die Dicke der Leiste in jedem Lauf dieser Abnahme
X0, X1 = 140, 670   # zwischen den Knoepfen links und der Uhr rechts
ZOOM = 2
BESCHR_H = 26       # die Zeile ueber jedem Streifen
RAND = 8


def var_von(im):
    """Die Streuung des Leistenstreifens -- dieselbe wie `glascheck var`."""
    px = [im.getpixel(p) for p in glascheck.leiste(im, HOEHE, X0, X1)]
    l = [glascheck.hell(p) for p in px]
    m = sum(l) / len(l)
    var = sum((v - m) ** 2 for v in l) / len(l)
    return int(var * 100), len(set(px))


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    ziel = argv[1]
    reihen = []
    for a in argv[2:]:
        if "=" not in a:
            print("streifen.py: '%s' ist kein <bild>=<beschriftung>" % a)
            return 2
        pfad, text = a.split("=", 1)
        im = Image.open(pfad).convert("RGB")
        w, h = im.size
        var, farben = var_von(im)
        streifen = im.crop((X0, h - HOEHE, min(X1, w), h))
        streifen = streifen.resize(
            (streifen.width * ZOOM, streifen.height * ZOOM), Image.NEAREST)
        reihen.append((streifen, "%s  --  var %d, %d Farben"
                       % (text, var, farben)))
        print("streifen: %s var %d farben %d" % (os.path.basename(pfad),
                                                 var, farben))
    bw = max(r[0].width for r in reihen) + 2 * RAND
    bh = RAND + sum(r[0].height + BESCHR_H for r in reihen) + RAND
    aus = Image.new("RGB", (bw, bh), (24, 24, 28))
    d = ImageDraw.Draw(aus)
    # Die Beschriftung wird mit der mitgelieferten Schrift von Pillow
    # gemalt -- sie ist nicht die Schrift des Systems und soll es auch
    # nicht sein: hier spricht das Werkzeug ueber das Bild und nicht
    # das System in ihm.
    font = ImageFont.load_default(16)
    y = RAND
    for streifen, text in reihen:
        d.text((RAND, y + 4), text, fill=(240, 240, 240), font=font)
        y += BESCHR_H
        aus.paste(streifen, (RAND, y))
        d.rectangle([RAND - 1, y - 1, RAND + streifen.width,
                     y + streifen.height], outline=(90, 90, 100))
        y += streifen.height
    aus.save(ziel)
    print("streifen: %s %dx%d aus %d Reihen"
          % (ziel, bw, bh, len(reihen)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
