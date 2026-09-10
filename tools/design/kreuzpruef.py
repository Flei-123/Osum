#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/kreuzpruef.py -- IST DAS X DOPPELT GEZEICHNET?
#
# Justins Foto vom 10.09. 18:39: das Schliesskreuz ist zerfranst, mit
# einem fetten schraegen Zusatzbalken. Minimieren (ein Strich) und
# Maximieren (ein Kasten) sind sauber. Der Unterschied steht in
# kernel/wm.fi, cg_bauen:
#
#     MIN:  nach/linie, strichen(0)                  -- EIN Strich
#     MAX:  cg_kasten -> strichen(1)                 -- EIN Zug
#     X:    nach/linie, strichen(0)                  -- Strich 1
#           nach/linie, strichen(0)                  -- Strich 2  <---
#
# `strichen` legt die UMRISSE des Strichs in den Pfad. Zwei Aufrufe
# heissen zwei Umrisse im SELBEN Pfad, und `rastern(NICHTNULL)` fuellt
# nach der Nichtnull-Regel: wo sich die beiden Umrisse ueberlappen --
# in der Mitte des Kreuzes und an den vier Enden -- addieren sich die
# Umlaufzahlen, statt sich aufzuheben.
#
# DIESES WERKZEUG MISST DAS, ohne den Kern zu booten: es baut dieselben
# zwei Faelle in Python nach (dieselbe Geometrie, dieselbe Regel) und
# zaehlt die Bildpunkte, die MEHR ALS EINMAL bedeckt werden.
#
#   ein sauberes X:  jeder Bildpunkt hoechstens einmal -> 0
#   ein doppeltes X: die Kreuzungsflaeche zaehlt doppelt -> > 0
#
# Kein Ersatz fuer den Screenshot, sondern die schnelle Vorprobe: sie
# sagt in einer Sekunde, ob der Verdacht ueberhaupt stimmt.
import sys

EINS = 64  # dieselbe Festkommaeinheit wie vektor.EINS (Annahme, s.u.)


def strich_umriss(x0, y0, x1, y1, sb):
    """Die vier Eckpunkte des Rechtecks um die Strecke, wie `strichen`
    sie legt. Runde Enden lassen wir weg -- fuer die Frage "ueberlappen
    sich zwei Umrisse" sind sie unerheblich."""
    dx, dy = x1 - x0, y1 - y0
    ln = (dx * dx + dy * dy) ** 0.5
    if ln == 0:
        return []
    nx, ny = -dy / ln * sb / 2, dx / ln * sb / 2
    return [(x0 + nx, y0 + ny), (x1 + nx, y1 + ny),
            (x1 - nx, y1 - ny), (x0 - nx, y0 - ny)]


def innen(poly, px, py):
    """Umlaufzahl eines Punktes gegen ein Polygon (Nichtnull-Regel)."""
    w = 0
    n = len(poly)
    for i in range(n):
        ax, ay = poly[i]
        bx, by = poly[(i + 1) % n]
        if ay <= py < by or by <= py < ay:
            t = (py - ay) / (by - ay)
            xx = ax + t * (bx - ax)
            if xx > px:
                w += 1 if by > ay else -1
    return w


def messen(d, sb, zwei):
    """Wie oft wird jeder Bildpunkt bedeckt? `zwei`=True baut das X aus
    ZWEI getrennten Strichen (heutiger Stand), False aus einem
    zusammenhaengenden Zug."""
    if zwei:
        umrisse = [strich_umriss(0, 0, d, d, sb),
                   strich_umriss(d, 0, 0, d, sb)]
    else:
        umrisse = [strich_umriss(0, 0, d, d, sb)]
    mehrfach = 0
    gesamt = 0
    for py in range(-2, d + 3):
        for px in range(-2, d + 3):
            n = 0
            for u in umrisse:
                if u and innen(u, px + 0.5, py + 0.5) != 0:
                    n += 1
            if n > 0:
                gesamt += 1
            if n > 1:
                mehrfach += 1
    return gesamt, mehrfach


if __name__ == '__main__':
    print("KREUZPRUEF -- ueberlappen sich die zwei Striche des X?")
    print()
    print("%-30s %8s %10s %s" % ("Fall", "bedeckt", "mehrfach", "Urteil"))
    fehler = 0
    for sk in (1, 2, 3):
        d = 10 * sk
        sb = 3 * sk / 2.0
        ges, mehr = messen(d, sb, True)
        urteil = "SAUBER" if mehr == 0 else "DOPPELT GEZEICHNET"
        if mehr > 0:
            fehler += 1
        print("%-30s %8d %10d %s"
              % ("X, zwei Striche (uisc=%d)" % sk, ges, mehr, urteil))
    print()
    for sk in (1, 2, 3):
        d = 10 * sk
        sb = 3 * sk / 2.0
        ges, mehr = messen(d, sb, False)
        print("%-30s %8d %10d %s"
              % ("Gegenprobe: EIN Strich (uisc=%d)" % sk, ges, mehr,
                 "SAUBER" if mehr == 0 else "DOPPELT"))
    print()
    if fehler:
        print("BEFUND: das X wird an der Kreuzung MEHRFACH bedeckt.")
        print("        Genau das sieht Justin als fetten Zusatzbalken.")
        sys.exit(1)
    print("BEFUND: keine Mehrfachbedeckung.")
