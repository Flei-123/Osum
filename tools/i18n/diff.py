#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/i18n/diff.py -- WIE VERSCHIEDEN SIND ZWEI BILDSCHIRMFOTOS?
#
#   python3 tools/i18n/diff.py <a.ppm> <b.ppm> [x y w h]
#
# Gibt eine Zeile aus: "<n> von <ganz> Bildpunkten verschieden (<p>%)".
#
# WOZU. Runde I18N behauptet, dass derselbe Bildschirm auf Englisch und
# auf Deutsch ANDERS aussieht. Alle anderen Messungen dieser Runde
# koennten stimmen -- der Mitschnitt, die Schluesselzahl, die
# bildpunktgenaue Pruefung EINER Zeile -- und der Schirm trotzdem
# zweimal gleich sein, etwa weil beide Fotos aus demselben Lauf stammen.
# Diese Zahl schliesst das aus.
#
# Umgekehrt ist sie auch eine Obergrenze: waeren die Bilder zu 90%
# verschieden, waere nicht die Sprache gewechselt, sondern etwas anderes
# kaputt.
import sys


def lies(pfad):
    d = open(pfad, "rb").read()
    if d[:2] != b"P6":
        raise SystemExit("%s ist kein P6-PPM" % pfad)
    # Kopf: P6, Breite, Hoehe, Maximalwert -- durch Leerraum getrennt,
    # Kommentare mit '#'.
    felder = []
    i = 2
    while len(felder) < 3:
        while i < len(d) and d[i:i + 1].isspace():
            i += 1
        if d[i:i + 1] == b"#":
            while i < len(d) and d[i] != 10:
                i += 1
            continue
        j = i
        while j < len(d) and not d[j:j + 1].isspace():
            j += 1
        felder.append(int(d[i:j]))
        i = j
    i += 1
    w, h, _mx = felder
    return w, h, d[i:i + w * h * 3]


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    aw, ah, a = lies(sys.argv[1])
    bw, bh, b = lies(sys.argv[2])
    if (aw, ah) != (bw, bh):
        print("verschiedene Groessen: %dx%d gegen %dx%d" % (aw, ah, bw, bh))
        return 1
    if len(sys.argv) >= 7:
        x0, y0, w, h = (int(v) for v in sys.argv[3:7])
    else:
        x0, y0, w, h = 0, 0, aw, ah
    n = 0
    ganz = 0
    for y in range(y0, min(y0 + h, ah)):
        zeile = y * aw * 3
        for x in range(x0, min(x0 + w, aw)):
            o = zeile + x * 3
            ganz += 1
            if a[o:o + 3] != b[o:o + 3]:
                n += 1
    if ganz == 0:
        print("0 von 0 Bildpunkten verschieden (0%)")
        return 1
    print("%d von %d Bildpunkten verschieden (%d%%)"
          % (n, ganz, n * 100 // ganz))
    return 0 if n else 1


sys.exit(main())
