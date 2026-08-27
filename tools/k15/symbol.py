#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/k15/symbol.py -- aus einer Zeichnung ein BILD.

Runde K15, zweiter Nachtrag. Ein Programm ist ein Buendel
(`/apps/<name>.prog/`), und in ein Buendel gehoert ein Symbol. Der erste
Nachtrag hatte statt eines Symbols sechs Hexziffern in einer Textdatei --
ehrlich, solange dieses System kein Bild lesen konnte, aber eben kein
Bild.

DAS FORMAT HEISST OSYM UND HAT ZWOELF OKTETTE KOPF:

    +0   "OSYM"                vier Oktette
    +4   Breite                vier Oktette, klein zuerst
    +8   Hoehe                 vier Oktette, klein zuerst
    +12  Breite * Hoehe Bildpunkte zu vier Oktetten: B, G, R, A

WARUM NICHT PNG. PNG braucht einen Deflate-Leser (den gibt es,
`kernel/user/flate.fi`), einen Filterschritt je Zeile, eine
Farbtabelle, Interlacing und CRC32 -- mehrere hundert Zeilen fuer
sechzehn mal sechzehn Bildpunkte, die aus einem Buendel kommen, das der
Bauer dieses Systems selbst schreibt. Vier Oktette Kennung und zwei
Zahlen tun dasselbe und sind an einer Stelle nachzurechnen. Wer spaeter
PNG lesen will, tut es; dieses Format steht ihm nicht im Weg, weil die
Kennung am Anfang steht.

DIE QUELLE IST TEXT, und das ist Absicht: ein Symbol, das als
Oktettklumpen im Baum liegt, kann niemand in einem Unterschied lesen.

    # X = 4a90d0        eine Farbe je Zeichen, RGB in sechs Hexziffern
    # o = ffffff
    # . =               nichts dahinter heisst DURCHSICHTIG
    ................
    ..XXXXXXXXXXXX..
    ...

Verwendung:
    symbol.py <zeichnung.txt> <ausgabe>
    symbol.py --pruefe <ausgabe> <zeichnung.txt>   liest zurueck
"""

import struct
import sys


def lies(pfad):
    palette = {}
    zeilen = []
    for roh in open(pfad, encoding="ascii").read().splitlines():
        if roh.startswith("#"):
            teil = roh[1:].strip()
            if "=" in teil:
                zeichen, _, wert = teil.partition("=")
                zeichen = zeichen.strip()
                wert = wert.strip()
                if len(zeichen) != 1:
                    raise SystemExit(
                        "symbol: '%s' ist kein einzelnes Zeichen" % zeichen)
                if not wert:
                    palette[zeichen] = None  # durchsichtig
                else:
                    if len(wert) != 6:
                        raise SystemExit(
                            "symbol: '%s' sind nicht sechs Hexziffern" % wert)
                    palette[zeichen] = int(wert, 16)
            continue
        if roh.strip() == "":
            continue
        zeilen.append(roh)
    if not zeilen:
        raise SystemExit("symbol: %s hat keine Zeile Bild" % pfad)
    breite = len(zeilen[0])
    for i, z in enumerate(zeilen):
        if len(z) != breite:
            raise SystemExit("symbol: Zeile %d ist %d Zeichen breit, die "
                             "erste %d" % (i + 1, len(z), breite))
    for z in zeilen:
        for c in z:
            if c not in palette:
                raise SystemExit("symbol: '%s' steht in keiner Palette" % c)
    return palette, zeilen


def baue(pfad):
    palette, zeilen = lies(pfad)
    h = len(zeilen)
    w = len(zeilen[0])
    aus = bytearray(b"OSYM")
    aus += struct.pack("<II", w, h)
    for z in zeilen:
        for c in z:
            rgb = palette[c]
            if rgb is None:
                aus += bytes(4)
            else:
                aus += bytes(((rgb & 255), (rgb >> 8) & 255,
                              (rgb >> 16) & 255, 255))
    return bytes(aus)


def zurueck(pfad):
    """Das Bild wieder als Farben lesen -- die zweite Umsetzung, gegen die
    der Testlaeufer den Schirm haelt. Sie liest die DATEI, nicht die
    Zeichnung, und rechnet deshalb wirklich nach, was ausgeliefert wurde.
    """
    d = open(pfad, "rb").read()
    if len(d) < 12 or d[:4] != b"OSYM":
        raise SystemExit("symbol: %s faengt nicht mit OSYM an" % pfad)
    w, h = struct.unpack_from("<II", d, 4)
    if len(d) < 12 + w * h * 4:
        raise SystemExit("symbol: %s ist zu kurz fuer %dx%d" % (pfad, w, h))
    aus = []
    for y in range(h):
        reihe = []
        for x in range(w):
            b, g, r, a = d[12 + (y * w + x) * 4:12 + (y * w + x) * 4 + 4]
            reihe.append(None if a == 0 else (r << 16) | (g << 8) | b)
        aus.append(reihe)
    return w, h, aus


def main(argv):
    if len(argv) >= 4 and argv[1] == "--pruefe":
        w, h, bild = zurueck(argv[2])
        palette, zeilen = lies(argv[3])
        if h != len(zeilen) or w != len(zeilen[0]):
            print("symbol: %dx%d im Bild, %dx%d in der Zeichnung"
                  % (w, h, len(zeilen[0]), len(zeilen)))
            return 1
        falsch = 0
        for y in range(h):
            for x in range(w):
                if bild[y][x] != palette[zeilen[y][x]]:
                    falsch += 1
        if falsch:
            print("symbol: %d von %d Bildpunkten anders" % (falsch, w * h))
            return 1
        print("symbol: %dx%d, %d Bildpunkte, alle gleich" % (w, h, w * h))
        return 0
    if len(argv) != 3:
        print(__doc__)
        return 2
    d = baue(argv[1])
    with open(argv[2], "wb") as f:
        f.write(d)
    print("symbol: %s  %d Oktette" % (argv[2], len(d)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
