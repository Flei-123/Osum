#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/snip/pixel.py -- DAS BILD GEGEN DEN RAHMENPUFFER, Punkt fuer Punkt.

    pixel.py <bild.rgb> <bw> <bh> <schirm.ppm> <ox> <oy> [--erlaubt N]
             [--nichtim x0 y0 x1 y1]...

`bild.rgb` ist das, was `pngcheck.py --raw` aus dem PNG von Osum
herausgeholt hat: w*h*3 Oktette. `schirm.ppm` ist das, was QEMU im
selben Augenblick auf seiner Bildflaeche hatte (`screendump`). `ox`/`oy`
sagt, wo im Bildschirm der Ausschnitt anfing.

WARUM DAS DIE EIGENTLICHE MESSUNG IST. Ein PNG kann formal
tadellos sein und trotzdem das falsche Bild enthalten -- um zwei Zeilen
verschoben, mit vertauschten Farbkanaelen, mit der Zeilenlaenge des
Rahmenpuffers statt der Breite. Nichts davon sieht man einem gueltigen
PNG an; alles davon faellt hier auf.

`--nichtim` nimmt Rechtecke aus dem Vergleich heraus -- fuer die
Stellen, an denen im Bild absichtlich etwas anderes steht als auf dem
Schirm (das Overlay, das Aufnahmezeichen, eine Marke). Jedes davon wird
gemeldet, damit ein Ausschluss nicht heimlich waechst.

`--erlaubt` ist die Zahl der Bildpunkte, die abweichen duerfen. Sie ist
0, wenn nichts anderes gesagt wird, und das ist der Punkt.
"""
import sys


def lies_ppm(pfad):
    roh = open(pfad, "rb").read()
    if not roh.startswith(b"P6"):
        raise SystemExit("  FEHLER %s ist kein P6-PPM" % pfad)
    felder = []
    at = 2
    while len(felder) < 3:
        while at < len(roh) and roh[at:at + 1].isspace():
            at += 1
        if roh[at:at + 1] == b"#":
            while at < len(roh) and roh[at] != 10:
                at += 1
            continue
        anf = at
        while at < len(roh) and not roh[at:at + 1].isspace():
            at += 1
        felder.append(int(roh[anf:at]))
    at += 1
    w, h, mx = felder
    if mx != 255:
        raise SystemExit("  FEHLER %s hat maxval %d" % (pfad, mx))
    return w, h, roh[at:at + w * h * 3]


def main():
    if len(sys.argv) < 7:
        print(__doc__)
        return 2
    rgb_pfad, bw, bh, ppm_pfad, ox, oy = sys.argv[1:7]
    bw, bh, ox, oy = int(bw), int(bh), int(ox), int(oy)
    erlaubt = 0
    aus = []
    rest = sys.argv[7:]
    i = 0
    while i < len(rest):
        if rest[i] == "--erlaubt":
            erlaubt = int(rest[i + 1])
            i += 2
        elif rest[i] == "--nichtim":
            aus.append(tuple(int(v) for v in rest[i + 1:i + 5]))
            i += 5
        else:
            i += 1

    bild = open(rgb_pfad, "rb").read()
    if len(bild) != bw * bh * 3:
        print("  FEHLER %s hat %d Oktette, erwartet %d"
              % (rgb_pfad, len(bild), bw * bh * 3))
        return 1
    sw, sh, schirm = lies_ppm(ppm_pfad)
    if ox + bw > sw or oy + bh > sh:
        print("  FEHLER der Ausschnitt (%d,%d %dx%d) liegt nicht im Schirm "
              "(%dx%d)" % (ox, oy, bw, bh, sw, sh))
        return 1

    for r in aus:
        print("        ausgenommen: %d,%d bis %d,%d" % r)

    schlecht = 0
    erste = None
    geprueft = 0
    for y in range(bh):
        zb = y * bw * 3
        zs = ((oy + y) * sw + ox) * 3
        for x in range(bw):
            drin = False
            for (x0, y0, x1, y1) in aus:
                if x0 <= x < x1 and y0 <= y < y1:
                    drin = True
                    break
            if drin:
                continue
            geprueft += 1
            a = bild[zb + x * 3:zb + x * 3 + 3]
            b = schirm[zs + x * 3:zs + x * 3 + 3]
            if a != b:
                schlecht += 1
                if erste is None:
                    erste = (x, y, tuple(a), tuple(b))
    print("SNIP-PIXEL: %d von %d Bildpunkten verglichen, %d verschieden"
          % (geprueft, bw * bh, schlecht))
    if erste is not None:
        print("        erste Abweichung bei %d,%d: Bild %s, Schirm %s"
              % erste)
    if schlecht > erlaubt:
        print("  FEHLER mehr als %d Abweichungen" % erlaubt)
        return 1
    print("  OK    das PNG ist der Rahmenpuffer, Bildpunkt fuer Bildpunkt")
    return 0


if __name__ == "__main__":
    sys.exit(main())
