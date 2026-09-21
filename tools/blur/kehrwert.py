#!/usr/bin/env python3
"""tools/blur/kehrwert.py -- DIE KEHRWERTTAFEL DES BLURS BEWEISEN.

Der zweifache Kastenfilter teilt je Bildpunkt und Kanal eine Summe
durch die Anzahl der aufsummierten Bildpunkte. Eine ganzzahlige
Division kostet auf dieser Maschine ein Vielfaches einer
Multiplikation, und es sind ZWOELF davon je Bildpunkt (vier Durchgaenge
mal drei Kanaele). Gemessen hat das den Filter mehr als verfuenffacht
(Startmenue 15,32 ms gegen 3,16 ms).

Also wird mit dem Kehrwert multipliziert. Das ist nur dann erlaubt,
wenn es fuer JEDEN vorkommenden Fall EXAKT dasselbe Ergebnis liefert
wie die Division -- auf einer weichgezeichneten Flaeche ist schon ein
Fehler von EINER Stufe als Streifen sichtbar (dieselbe Sorte Fehler,
die `blendcheck.py` in diesem Projekt schon einmal gejagt hat).

Die erste Fassung rundete den KEHRWERT auf ((1<<16)+n-1)/n und lag um
bis zu 16 Stufen daneben. Richtig ist Aufrunden im ZAEHLER.

Diese Probe geht den Raum VOLLSTAENDIG durch: jedes n von 1 bis 2*16+1
und jede Summe von 0 bis n*255.
"""
RADIUS_MAX = 16
SHIFT = 19

def main():
    nmax = 2 * RADIUS_MAX + 1
    rund = 1 << (SHIFT - 1)
    schlimm = 0
    faelle = 0
    for n in range(1, nmax + 1):
        rec = ((1 << SHIFT) + n - 1) // n
        if rec >> 32:
            print(f"  n={n}: Kehrwert passt nicht in 32 Bit"); return 1
        for summe in range(0, n * 255 + 1):
            exakt = (summe + n // 2) // n
            got = (summe * rec + rund) >> SHIFT
            faelle += 1
            d = abs(exakt - got)
            if d > schlimm:
                schlimm = d
    print(f"BLUR-KEHRWERT: shift={SHIFT}, n=1..{nmax}, {faelle} Faelle geprueft")
    if schlimm == 0:
        print("  OK    jeder Fall EXAKT wie die Division")
        return 0
    print(f"  FEHL  groesster Fehler {schlimm}")
    return 1

raise SystemExit(main())
