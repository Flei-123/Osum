#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/bridge/ppmvergleich.py -- das Bild von INNEN gegen das von AUSSEN.

    ppmvergleich.py <innen.ppm> <aussen.ppm>

WIE HIER VERGLICHEN WIRD, UND WARUM NICHT EINFACH ALLES.

Zwei Bilder desselben Schirms, ein paar Sekunden auseinander -- und
dazwischen hat `serial.put` weitergespiegelt (kernel/gfx/fb.fi, `S_ECHO`):
Osum meldet auf der seriellen Leitung, dass es fertig ist, und JEDES
dieser Oktette landet auch auf dem Schirm. Der Wirt fotografiert danach
und sieht darum ein paar Textzeilen MEHR.

Gemessen im ersten Anlauf: 108 168 abweichende Oktette, verteilt auf 611
von 800 Zeilen, in Baendern mit 12 bis 13 Zeilen Abstand -- genau die
Hoehe einer Textzeile. Es war also die Konsole und nichts sonst.

Ein Vergleich ueber das ganze Bild beantwortet damit die falsche Frage.
Die richtige lautet: STIMMEN DIE BILDPUNKTE, DIE SICH NICHT GEAENDERT
HABEN? Also werden beide Zahlen ausgerechnet und BEIDE ausgegeben. Die
Zusage ist die zweite, und sie ist scharf: die Bildpunkte kommen aus dem
Kern von innen und aus QEMU von aussen, und der Wirt kann von einem
Fehler im Kern nicht belogen werden.
"""
import sys


def ppm(pfad):
    d = open(pfad, "rb").read()
    if not d.startswith(b"P6"):
        raise SystemExit("keine P6-Datei: " + pfad)
    felder = []
    at = 2
    while len(felder) < 3:
        while at < len(d) and d[at:at + 1].isspace():
            at += 1
        if d[at:at + 1] == b"#":
            while d[at:at + 1] not in (b"\n", b""):
                at += 1
            continue
        s = at
        while at < len(d) and not d[at:at + 1].isspace():
            at += 1
        felder.append(int(d[s:at]))
    at += 1
    w, h, _mx = felder
    return w, h, d[at:at + w * h * 3]


def main():
    iw, ih, ib = ppm(sys.argv[1])
    aw, ah, ab = ppm(sys.argv[2])
    print("innen  %dx%d  %d Oktette" % (iw, ih, len(ib)))
    print("aussen %dx%d  %d Oktette" % (aw, ah, len(ab)))
    if (iw, ih) != (aw, ah):
        print("MASSE VERSCHIEDEN")
        return 1
    if len(ib) != iw * ih * 3:
        print("DAS BILD VON INNEN IST UNVOLLSTAENDIG: %d statt %d"
              % (len(ib), iw * ih * 3))
        return 1
    print("das Bild von innen ist VOLLSTAENDIG: %d Oktette" % len(ib))

    zeile = iw * 3
    verschieden = [y for y in range(ih)
                   if ib[y * zeile:(y + 1) * zeile] != ab[y * zeile:(y + 1) * zeile]]
    vs = set(verschieden)
    gleich = ih - len(verschieden)
    print("Zeilen gleich: %d von %d" % (gleich, ih))
    print("Zeilen verschieden: %d" % len(verschieden))

    # Die gleichen Zeilen Oktett fuer Oktett -- die eigentliche Zusage.
    anders = 0
    for y in range(ih):
        if y in vs:
            continue
        o = y * zeile
        if ib[o:o + zeile] != ab[o:o + zeile]:
            for i in range(o, o + zeile):
                if ib[i] != ab[i]:
                    anders += 1
    print("abweichende Oktette in den gleichen Zeilen: %d" % anders)

    # Ein schwarzes Bild waere auch "gleich" -- also nachsehen, ob
    # ueberhaupt etwas darauf ist.
    nichtschwarz = sum(1 for i in range(0, len(ib), 3)
                       if ib[i] or ib[i + 1] or ib[i + 2])
    print("nicht-schwarze Bildpunkte innen: %d von %d" % (nichtschwarz, iw * ih))

    # Passt der Abstand der verschiedenen Zeilen zu einer Textzeile?
    if verschieden:
        baender = []
        s0 = verschieden[0]
        pv = verschieden[0]
        for y in verschieden[1:]:
            if y != pv + 1:
                baender.append((s0, pv))
                s0 = y
            pv = y
        baender.append((s0, pv))
        print("Baender verschiedener Zeilen: %d, erste: %s"
              % (len(baender), baender[:4]))

    if gleich > 0 and anders == 0 and nichtschwarz > 1000:
        print("GLEICH")
        return 0
    print("UNGLEICH")
    return 1


if __name__ == "__main__":
    sys.exit(main())
