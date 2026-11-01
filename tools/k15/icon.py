#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/k15/icon.py -- aus einer Zeichnung ein BILD.

Runde K15, zweiter Nachtrag. Ein Programm ist ein Buendel
(`/apps/<name>.osp/`), und in ein Buendel gehoert ein Symbol. Der erste
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

    ................
    ..XXXXXXXXXXXX..
    ...

ROLLEN STATT WERTE -- RUNDE NETVIEW, NACHTRAG. Ein Symbol, das in einem
hellen und in einem dunklen Farbschema richtig aussehen soll, darf seine
Farbe nicht selbst kennen. Ein Palettenwert, der mit `@` anfaengt, ist
darum keine Farbe, sondern eine ROLLE:


Sie stehen im DECKUNGSOKTETT und nicht in den Farboktetten: 0 heisst
durchsichtig wie bisher, 255 heisst "die drei Oktette sind die Farbe"
wie bisher, und 1 bis 5 heissen "hol dir die Farbe aus dem Schema".
Jedes Symbol, das es vor diesem Nachtrag gab, traegt weiter 0 und 255
und aendert sich um kein Oktett -- gemessen in tools/k15/run.sh, das
alle fuenf Buendelsymbole Punkt fuer Punkt zurueckliest.

Verwendung:
    icon.py <zeichnung.txt> <ausgabe>
    icon.py --pruefe <ausgabe> <zeichnung.txt>   liest zurueck
"""

import struct
import sys

ROLLEN = {
    "ink": 1,
    "dim": 2,
    "accent": 3,
    "warn": 4,
    "panel": 5,
}


def read_2(path_2):
    palette = {}
    zeilen = []
    for roh in open(path_2, encoding="ascii").read().splitlines():
        if roh.startswith("#"):
            part = roh[1:].strip()
            if "=" in part:
                zeichen, _, value = part.partition("=")
                zeichen = zeichen.strip()
                value = value.strip()
                if len(zeichen) != 1:
                    raise SystemExit(
                        "symbol: '%s' ist kein einzelnes Zeichen" % zeichen)
                if not value:
                    palette[zeichen] = None
                elif value.startswith("@"):
                    name = value[1:]
                    if name not in ROLLEN:
                        raise SystemExit(
                            "symbol: '@%s' ist keine Rolle (%s)"
                            % (name, ", ".join(sorted(ROLLEN))))
                    palette[zeichen] = ("rolle", ROLLEN[name])
                else:
                    if len(value) != 6:
                        raise SystemExit(
                            "symbol: '%s' sind nicht sechs Hexziffern" % value)
                    palette[zeichen] = int(value, 16)
            continue
        if roh.strip() == "":
            continue
        zeilen.append(roh)
    if not zeilen:
        raise SystemExit("symbol: %s hat keine Zeile Bild" % path_2)
    width_2 = len(zeilen[0])
    for i, z in enumerate(zeilen):
        if len(z) != width_2:
            raise SystemExit("symbol: Zeile %d ist %d Zeichen breit, die "
                             "erste %d" % (i + 1, len(z), width_2))
    for z in zeilen:
        for c in z:
            if c not in palette:
                raise SystemExit("symbol: '%s' steht in keiner Palette" % c)
    return palette, zeilen


def build(path_2):
    palette, zeilen = read_2(path_2)
    h = len(zeilen)
    w = len(zeilen[0])
    aus = bytearray(b"OSYM")
    aus += struct.pack("<II", w, h)
    for z in zeilen:
        for c in z:
            rgb = palette[c]
            if rgb is None:
                aus += bytes(4)
            elif isinstance(rgb, tuple):
                aus += bytes((0, 0, 0, rgb[1]))
            else:
                aus += bytes(((rgb & 255), (rgb >> 8) & 255,
                              (rgb >> 16) & 255, 255))
    return bytes(aus)


def back(path_2):
    d = open(path_2, "rb").read()
    if len(d) < 12 or d[:4] != b"OSYM":
        raise SystemExit("symbol: %s faengt nicht mit OSYM an" % path_2)
    w, h = struct.unpack_from("<II", d, 4)
    if len(d) < 12 + w * h * 4:
        raise SystemExit("symbol: %s ist zu kurz fuer %dx%d" % (path_2, w, h))
    aus = []
    for y in range(h):
        reihe = []
        for x in range(w):
            b, g, r, a = d[12 + (y * w + x) * 4:12 + (y * w + x) * 4 + 4]
            if a == 0:
                reihe.append(None)
            elif a != 255 and w >= 32 and h >= 32:
                reihe.append(None)
            elif a != 255:
                reihe.append(("rolle", a))
            else:
                reihe.append((r << 16) | (g << 8) | b)
        aus.append(reihe)
    return w, h, aus


def main(argv):
    if len(argv) >= 4 and argv[1] == "--pruefe" and argv[3].endswith(".osym"):
        import os
        import symjoin
        want = symjoin.joined(os.path.dirname(argv[3]) or ".")
        if open(argv[2], "rb").read() == want:
            print("symbol.osym, %d Oktette, gleich" % len(want))
            return 0
        print("symbol: the image does not carry the octets of %s (with the row images)" % argv[3])
        return 1
    if len(argv) >= 4 and argv[1] == "--pruefe":
        w, h, image = back(argv[2])
        palette, zeilen = read_2(argv[3])
        if h != len(zeilen) or w != len(zeilen[0]):
            print("symbol: %dx%d in the image, %dx%d in the drawing"
                  % (w, h, len(zeilen[0]), len(zeilen)))
            return 1
        wrong = 0
        for y in range(h):
            for x in range(w):
                if image[y][x] != palette[zeilen[y][x]]:
                    wrong += 1
        if wrong:
            print("symbol: %d of %d pixels different" % (wrong, w * h))
            return 1
        print("symbol: %dx%d, %d pixels, all equal" % (w, h, w * h))
        return 0
    if len(argv) != 3:
        print(__doc__)
        return 2
    d = build(argv[1])
    with open(argv[2], "wb") as f:
        f.write(d)
    print("symbol: %s  %d Oktette" % (argv[2], len(d)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
