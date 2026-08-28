#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/a11y/lupe.py -- DIE BILDSCHIRMLUPE IM BILD NACHRECHNEN.

    lupe.py <bild.ppm> <px> <py> <w> <h> <sx> <sy> <f> [rand]

Die Tafel steht bei (px, py) und ist w x h gross; sie zeigt den
Ausschnitt ab (sx, sy) um den Faktor f vergroessert.  Der Kernel SAGT
diese sechs Zahlen (`ax: mag ...`) -- dieses Programm rechnet sie im
BILD nach:

  Fuer jeden Bildpunkt der Tafel (ohne den Rahmen) muss gelten

      Tafel(px + c, py + r) == Schirm(sx + c/f, sy + r/f)

Das ist keine Aehnlichkeitspruefung und kein Histogramm: es ist derselbe
Bildpunkt, und wenn er es nicht ist, ist die Lupe falsch.  Genau deshalb
liest sie aus dem ZEICHENZIEL und nicht aus einem Fensterpuffer.

Rueckgabe 0, wenn alles stimmt.  Sonst 1 und die ersten Abweichungen.
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ppm import Bild


def main():
    if len(sys.argv) < 9:
        print(__doc__)
        return 2
    pfad = sys.argv[1]
    px, py, w, h, sx, sy, f = [int(v) for v in sys.argv[2:9]]
    b = Bild(pfad)
    if f < 1:
        print("Faktor %d" % f)
        return 1
    schlecht = 0
    geprueft = 0
    beispiele = []
    # Der Rahmen ist EINEN Bildpunkt breit und gehoert nicht zum
    # Ausschnitt -- er ist die Marke, an der ein Mensch die Tafel
    # findet.
    for r in range(1, h - 1):
        for c in range(1, w - 1):
            a = b.px(px + c, py + r)
            q = b.px(sx + c // f, sy + r // f)
            if a is None or q is None:
                continue
            geprueft += 1
            if a != q:
                schlecht += 1
                if len(beispiele) < 6:
                    beispiele.append("(%d,%d) Tafel %s <- Quelle (%d,%d) %s"
                                     % (px + c, py + r, a,
                                        sx + c // f, sy + r // f, q))
    if geprueft == 0:
        print("nichts geprueft -- liegt die Tafel im Bild?")
        return 1
    # DER RAHMEN. Ohne ihn waere "die Tafel ist da" nicht vom
    # Hintergrund zu unterscheiden, wenn der Ausschnitt zufaellig
    # einfarbig ist.
    ecke = b.px(px, py)
    # DIE RAHMENFARBE STEHT NICHT HIER. Sie kommt aus dem Farbschema
    # (die aktive Titelleiste), und der Kernel SAGT sie -- eine Zahl im
    # Testlaeufer waere eine zweite Fassung des Schemas, die ausgerechnet
    # dann falsch ist, wenn jemand das Schema wechselt.
    rahmen_ok = True
    if len(sys.argv) > 9:
        soll = int(sys.argv[9])
        rahmen_ok = ecke == ((soll >> 16) & 255, (soll >> 8) & 255,
                             soll & 255)
    if schlecht or not rahmen_ok:
        print("%d von %d Bildpunkten falsch, Rahmenecke %s"
              % (schlecht, geprueft, ecke))
        for z in beispiele:
            print("    " + z)
        return 1
    print("%d Bildpunkte, alle gleich der Quelle; Rahmen %s"
          % (geprueft, ecke))
    return 0


sys.exit(main())
