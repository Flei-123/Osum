#!/usr/bin/env python3
"""tools/k15/iconpixels.py -- steht das Symbol aus dem Buendel wirklich
auf dem Schirm? Bildpunkt fuer Bildpunkt.

Runde K15, zweiter Nachtrag. Das Symbol eines Programms ist seit diesem
Nachtrag eine DATEI im Buendel (`/apps/<name>.osp/symbol`, Format OSYM)
und keine Farbe mehr in einer Textdatei. Damit laesst sich die Zusage
"es wird gemalt" so pruefen, wie diese Runde Text prueft: nicht als
Flaeche gegen einen Mittelwert, sondern Punkt gegen Punkt gegen eine
ZWEITE Umsetzung -- hier `tools/k15/icon.py`, die die Datei
unabhaengig von Firn zurueckliest.

DIE LEHRE AUS RUNDE K7B GILT AUCH HIER: 87 Prozent richtige Bildpunkte
koennen bedeuten, dass der Hintergrund stimmt und das Bild fehlt. Also
werden nur die DECKENDEN Bildpunkte des Symbols gezaehlt -- die
durchsichtigen sagen ueber das Zeichnen nichts aus --, und es muss JEDER
davon stimmen.

Verwendung:
    iconpixels.py <schirm.ppm> <x> <y> <breite> <hoehe> <symbol> [<abweichung>]
    -> "ok <deckend> von <gepruefte> gleich"    Rueckgabe 0
    -> "falsch <n> von <deckend>"               Rueckgabe 1
"""

import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import icon as symmod  # noqa: E402


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


def main(argv):
    if len(argv) < 7:
        print(__doc__)
        return 2
    schirm, x, y, bw, bh, sym = argv[1], int(argv[2]), int(argv[3]), \
        int(argv[4]), int(argv[5]), argv[6]
    tol = int(argv[7]) if len(argv) > 7 else 0
    w, h, roh = ppm(schirm)
    sw, sh, bild = symmod.zurueck(sym)
    deckend = 0
    falsch = 0
    for r in range(min(bh, sh)):
        for c in range(min(bw, sw)):
            soll = bild[r][c]
            if soll is None:
                continue  # durchsichtig: darueber sagt das Bild nichts
            deckend += 1
            px, py = x + c, y + r
            if px >= w or py >= h:
                falsch += 1
                continue
            at = (py * w + px) * 3
            ist = (roh[at] << 16) | (roh[at + 1] << 8) | roh[at + 2]
            d = max(abs(((soll >> 16) & 255) - roh[at]),
                    abs(((soll >> 8) & 255) - roh[at + 1]),
                    abs((soll & 255) - roh[at + 2]))
            if d > tol:
                falsch += 1
    if deckend == 0:
        print("das Symbol hat keinen deckenden Bildpunkt")
        return 1
    if falsch:
        print("falsch %d von %d deckenden" % (falsch, deckend))
        return 1
    print("%d deckende Bildpunkte, alle gleich" % deckend)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
