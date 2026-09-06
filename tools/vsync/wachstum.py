#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/vsync/wachstum.py -- WAECHST DAS FENSTER WIRKLICH?

    wachstum.py <ppm> [<ppm> ...]

Die Zusage der Runde lautet: ein Fenster geht nicht schlagartig auf,
sondern SKALIERT von AN_SCALE0 (85 Prozent) auf volle Groesse und wird
dabei von durchsichtig nach deckend gemischt.

Das ist eine Aussage ueber eine BILDFOLGE und nicht ueber ein Bild.
Also wird je Foto die Flaeche des vorgefuehrten Fensters gezaehlt --
es hat einen kraeftigen blauen Rahmen (0x2E6FD9) um eine helle Flaeche
(0xE8EEF7), und beides kommt sonst nirgends im Bild vor.

Gezaehlt werden Bildpunkte, die dieser Farbe NAHE sind: waehrend der
Bewegung ist das Fenster ja gemischt, also weder ganz blau noch ganz
Hintergrund. Genau diese Zwischenwerte sind der Beweis -- ein Fenster,
das ohne Bewegung erscheint, ist in einem Bild gar nicht und im
naechsten voll da.

Ausgabe je Datei:

    <datei> flaeche=<n> gemischt=<n>

und am Ende die Kennzahlen der Folge:

    FOLGE bilder=<n> min=<n> max=<n> stufen=<n> gemischt_max=<n>

`stufen` ist die Zahl VERSCHIEDENER Flaechenwerte ueber der Folge --
das ist die eigentliche Zahl: 1 heisst "kein Wachsen", mehr heisst
"es sind Zwischengroessen im Bild angekommen".

Rueckgabe 0, wenn es mindestens drei Stufen gab, sonst 1.
"""
import sys

RAHMEN = (0x2E, 0x6F, 0xD9)
FLAECHE = (0xE8, 0xEE, 0xF7)
# Wie weit ein Bildpunkt von der reinen Farbe abweichen darf, um noch
# als "dieses Fenster" zu gelten. Waehrend der Mischung liegt er
# zwischen Fensterfarbe und Hintergrund, also grosszuegig.
NAH = 40


def ppm_lesen(pfad):
    with open(pfad, "rb") as f:
        roh = f.read()
    if not roh.startswith(b"P6"):
        raise ValueError("kein P6-PPM")
    felder = []
    i = 2
    while len(felder) < 3:
        while i < len(roh) and roh[i:i + 1].isspace():
            i += 1
        if roh[i:i + 1] == b"#":
            while i < len(roh) and roh[i] != 0x0A:
                i += 1
            continue
        j = i
        while j < len(roh) and not roh[j:j + 1].isspace():
            j += 1
        felder.append(int(roh[i:j]))
        i = j
    i += 1
    w, h, _ = felder
    return w, h, roh[i:i + w * h * 3]


def nahe(px, ziel):
    return (abs(px[0] - ziel[0]) <= NAH
            and abs(px[1] - ziel[1]) <= NAH
            and abs(px[2] - ziel[2]) <= NAH)


def zaehlen(pfad):
    w, h, dat = ppm_lesen(pfad)
    flaeche = 0
    gemischt = 0
    for k in range(0, len(dat) - 2, 3):
        px = (dat[k], dat[k + 1], dat[k + 2])
        if nahe(px, RAHMEN) or nahe(px, FLAECHE):
            flaeche += 1
            # Genau getroffen = fertig gemalt; daneben = gemischt, also
            # mitten in der Bewegung.
            if px != RAHMEN and px != FLAECHE:
                gemischt += 1
    _ = (w, h)
    return flaeche, gemischt


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    werte = []
    gmax = 0
    for pfad in sys.argv[1:]:
        try:
            f, g = zaehlen(pfad)
        except (OSError, ValueError) as e:
            print("%s FEHLER %s" % (pfad, e))
            return 2
        werte.append(f)
        gmax = max(gmax, g)
        print("%s flaeche=%d gemischt=%d" % (pfad.split("/")[-1], f, g))
    if not werte:
        return 2
    mitinhalt = [v for v in werte if v > 0]
    stufen = len(set(mitinhalt))
    print("FOLGE bilder=%d min=%d max=%d stufen=%d gemischt_max=%d"
          % (len(werte), min(werte), max(werte), stufen, gmax))
    return 0 if stufen >= 3 else 1


if __name__ == "__main__":
    sys.exit(main())
