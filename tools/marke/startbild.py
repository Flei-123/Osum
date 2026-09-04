#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/marke/startbild.py -- RUNDE STARTKNOPF: DAS LOGO IN DEN KERN.
#
# WARUM NICHT UEBER DIE SYMBOLSCHRIFT. Die Symbole dieses Systems sind
# eine SCHRIFT (assets/icons/icons.map -> tools/icons/build.py ->
# assets/osum-icons.ttf). Ein Zeichen einer Schrift hat GENAU EINEN
# Deckungsgrad je Bildpunkt und keine Farbe: der Zeichner gibt die
# Farbe an, die Schrift die Form. Justins Startzeichen ist dreifarbig
# (schwarzer Ring, weisser Kreis, hellblauer Diamant) -- das laesst
# sich in einer Schrift nicht darstellen, ohne es in drei Zeichen zu
# zerlegen und dreimal uebereinanderzumalen. Drei Zeichen, die nur
# zusammen ein Bild ergeben, sind ein Bild und keine Schrift.
#
# WARUM NICHT ALS DATEI IM ABBILD. Die Leiste soll ihren Knopf malen
# koennen, BEVOR irgendein Dateisystem eingehaengt ist -- auf Justins
# Brett ist genau das mehrfach schiefgegangen ("taskbar: icons=" und
# dann nichts mehr). Ein Knopf, dessen Bild von einem Dateizugriff
# abhaengt, ist ein Knopf, der manchmal leer ist.
#
# ALSO: die Bildpunkte werden hier zu Firn-Quelltext, kommen mit dem
# Programm in den Binaerbaum und haengen an nichts. Je Bildpunkt EIN
# Wort 0xAARRGGBB.
#
#   python3 tools/marke/startbild.py assets/marke kernel/user/marke_start.fi

import sys
from PIL import Image

GROESSEN = [16, 24, 32]


def lade(pfad, n):
    im = Image.open(pfad).convert("RGBA")
    if im.size != (n, n):
        im = im.resize((n, n), Image.LANCZOS)
    return im


def worte(im):
    out = []
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            r, g, b, a = im.getpixel((x, y))
            out.append((a << 24) | (r << 16) | (g << 8) | b)
    return out


def main():
    quelle = sys.argv[1] if len(sys.argv) > 1 else "assets/marke"
    ziel = sys.argv[2] if len(sys.argv) > 2 else "kernel/user/marke_start.fi"
    t = []
    t.append("// SPDX-License-Identifier: GPL-2.0-only\n")
    t.append("// kernel/user/marke_start.fi -- ERZEUGT, NICHT VON HAND\n")
    t.append("//   tools/marke/startbild.py assets/marke "
             "kernel/user/marke_start.fi\n")
    t.append("//\n")
    t.append("// Das Startzeichen von OrientOS als Bildpunkte, drei\n")
    t.append("// Groessen, je Bildpunkt ein Wort 0xAARRGGBB. Warum es hier\n")
    t.append("// steht und nicht in der Symbolschrift oder in einer Datei,\n")
    t.append("// steht im Kopf von tools/marke/startbild.py.\n\n")
    t.append("profile kernel\n\n")
    t.append("export { breit, punkt }\n\n")
    for n in GROESSEN:
        im = lade("%s/start-%d.png" % (quelle, n), n)
        w = worte(im)
        t.append("static mut b%d: [u64; %d] = [\n" % (n, len(w)))
        zeile = "    "
        for i, v in enumerate(w):
            s = "%d as u64" % v
            if i + 1 < len(w):
                s += ","
            if len(zeile) + len(s) > 72:
                t.append(zeile + "\n")
                zeile = "    "
            zeile += s + " "
        t.append(zeile.rstrip() + "\n]\n\n")
    t.append("// Welche der drei Groessen fuer eine gewuenschte Kantenlaenge\n")
    t.append("// genommen wird: die groesste, die noch hineinpasst. Ein Ring\n")
    t.append("// von einem Bildpunkt Staerke vertraegt keine Interpolation.\n")
    t.append("fn breit(wunsch: u64) -> u64 {\n")
    for n in reversed(GROESSEN):
        t.append("    if wunsch >= %d {\n        return %d\n    }\n" % (n, n))
    t.append("    return %d\n}\n\n" % GROESSEN[0])
    t.append("// Ein Bildpunkt, 0xAARRGGBB. Ausserhalb: durchsichtig.\n")
    t.append("fn punkt(n: u64, x: u64, y: u64) -> u64 {\n")
    t.append("    if x >= n || y >= n {\n        return 0\n    }\n")
    t.append("    let i: u64 = y * n + x\n")
    for n in GROESSEN:
        t.append("    if n == %d {\n        return b%d[(i) as usize]\n    }\n"
                 % (n, n))
    t.append("    return 0\n}\n")
    open(ziel, "w").write("".join(t))
    print("%s geschrieben (%d Groessen)" % (ziel, len(GROESSEN)))


main()
