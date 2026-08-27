#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/netview/checkshot.py -- steht das Symbol WIRKLICH auf dem Schirm?

Runde NETVIEW, Nachtrag. `tools/k15/iconpixels.py` kann das schon, aber
nur fuer Symbole mit festen Farben. Die Symbole dieser Runde tragen
ROLLEN (`@ink`, `@dim`, `@accent`, `@warn`) und keine Werte -- was auf
dem Schirm stehen MUSS, haengt also vom Farbschema ab, mit dem der Lauf
gebootet hat. Dieses Werkzeug loest die Rolle gegen die Schema-DATEI auf
und rechnet dann Punkt fuer Punkt.

DIE LEHRE AUS RUNDE K7B GILT WEITER: 87 Prozent richtige Bildpunkte
koennen heissen, dass der Hintergrund stimmt und das Bild fehlt. Also
werden nur die DECKENDEN Bildpunkte gezaehlt, und es muss JEDER von
ihnen stimmen.

UND EINE GEGENPROBE IST EINGEBAUT: `--nicht` verlangt, dass das Bild
dort NICHT steht. Ein Zeichen, das ueberall passt, misst nichts -- die
Stelle, an der `real` steht, muss leer bleiben, und das wird genauso
gerechnet wie das Vorhandensein.

Verwendung:
    schau.py <schirm.ppm> <x> <y> <zeichnung.txt> <schema> [--nicht]
    -> "ok <deckend> von <deckend> gleich"        Rueckgabe 0
    -> "falsch <n> von <deckend>"                 Rueckgabe 1
"""

import os
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HIER), "k15"))
import symbol as symmod  # noqa: E402
sys.path.insert(0, HIER)
import icons as iconmod  # noqa: E402


def ppm(pfad):
    d = open(pfad, "rb").read()
    if not d.startswith(b"P6"):
        raise SystemExit("kein P6-PPM: %s" % pfad)
    felder = []
    at = 2
    while len(felder) < 3:
        while at < len(d) and d[at:at + 1].isspace():
            at += 1
        if d[at:at + 1] == b"#":
            while d[at:at + 1] not in (b"\n", b""):
                at += 1
            continue
        anf = at
        while at < len(d) and not d[at:at + 1].isspace():
            at += 1
        felder.append(int(d[anf:at]))
    at += 1
    w, h, _ = felder
    return w, h, d[at:]


ROLLE_NAME = {v: k for k, v in symmod.ROLLEN.items()}


def main(argv):
    if len(argv) < 6:
        print(__doc__)
        return 2
    schirm, x, y, zeichnung, schema = (argv[1], int(argv[2]), int(argv[3]),
                                       argv[4], argv[5])
    nicht = "--nicht" in argv
    farben = iconmod.schema_lesen(schema)
    palette, zeilen = symmod.lies(zeichnung)
    w, h, roh = ppm(schirm)
    deckend = 0
    falsch = 0
    for r, zeile in enumerate(zeilen):
        for c, zeichen in enumerate(zeile):
            soll = palette[zeichen]
            if soll is None:
                continue  # durchsichtig: darueber sagt das Bild nichts
            if isinstance(soll, tuple):
                soll = farben[ROLLE_NAME[soll[1]]]
            deckend += 1
            px, py = x + c, y + r
            if px >= w or py >= h:
                falsch += 1
                continue
            at = (py * w + px) * 3
            if (roh[at] != ((soll >> 16) & 255)
                    or roh[at + 1] != ((soll >> 8) & 255)
                    or roh[at + 2] != (soll & 255)):
                falsch += 1
    if nicht:
        # DIE GEGENPROBE. Wenn dort nichts stehen soll, muessen sich die
        # meisten Bildpunkte unterscheiden -- ein einzelner Treffer ist
        # Zufall, ein vollstaendiger Treffer ist das Bild.
        if falsch * 4 >= deckend:
            print("ok nicht da: %d von %d anders" % (falsch, deckend))
            return 0
        print("da, sollte aber nicht: nur %d von %d anders" % (falsch, deckend))
        return 1
    if falsch:
        print("falsch %d von %d" % (falsch, deckend))
        return 1
    print("ok %d von %d gleich" % (deckend, deckend))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
