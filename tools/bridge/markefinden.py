#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/bridge/markefinden.py -- steht die neue Zeile WIRKLICH im Bild?

    markefinden.py <eins.ppm> <zwei.ppm>

DIE GEGENPROBE AUF DEN INHALT. Dass sich zwei Bilder unterscheiden, sagt
noch nicht, dass sie den Schirm zeigen -- zwei Aufnahmen von Rauschen
unterscheiden sich auch. Zwischen den beiden Aufnahmen hat Osum EINE
Textzeile geschrieben (`echo BRIDGE2-MARKE`), und die muss sich im
zweiten Bild als das wiederfinden, was sie ist: eine Reihe HELLER
Bildpunkte auf dunklem Grund, in EINER Zeilenhoehe, und im ersten Bild
an derselben Stelle nicht.

Es wird bewusst NICHT der Text gelesen (das waere eine Zeichenerkennung
und eine zweite Fehlerquelle). Gemessen wird die Helligkeitsverteilung:
* die Baender, in denen sich die Bilder unterscheiden, sind hoechstens
  eine Textzeile hoch (der Zeichensatz ist 16 Bildpunkte hoch),
* im zweiten Bild sind dort MEHR helle Bildpunkte als im ersten -- da
  ist Text dazugekommen, nicht weggegangen.
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
    w, h, _ = felder
    return w, h, d[at:at + w * h * 3]


def main():
    w, h, a = ppm(sys.argv[1])
    w2, h2, b = ppm(sys.argv[2])
    if (w, h) != (w2, h2):
        print("MASSE VERSCHIEDEN")
        return 1
    zeile = w * 3

    verschieden = [y for y in range(h)
                   if a[y * zeile:(y + 1) * zeile] != b[y * zeile:(y + 1) * zeile]]
    if not verschieden:
        print("KEINE ZEILE VERSCHIEDEN -- die Marke ist nirgends")
        return 1

    # Zusammenhaengende Baender.
    baender = []
    s0 = verschieden[0]
    pv = verschieden[0]
    for y in verschieden[1:]:
        if y != pv + 1:
            baender.append((s0, pv))
            s0 = y
        pv = y
    baender.append((s0, pv))
    print("verschiedene Baender: %s" % baender)
    hoch = max(e - s + 1 for s, e in baender)
    print("hoechstes Band: %d Zeilen (eine Textzeile ist 16)" % hoch)

    def hell(bild, von, bis):
        n = 0
        for y in range(von, bis + 1):
            o = y * zeile
            for i in range(o, o + zeile, 3):
                if bild[i] > 96 or bild[i + 1] > 96 or bild[i + 2] > 96:
                    n += 1
        return n

    ha = sum(hell(a, s, e) for s, e in baender)
    hb = sum(hell(b, s, e) for s, e in baender)
    print("helle Bildpunkte in diesen Baendern: eins=%d zwei=%d" % (ha, hb))

    if hoch <= 40 and hb > ha:
        print("MARKE-GEFUNDEN")
        return 0
    print("MARKE-NICHT-GEFUNDEN")
    return 1


if __name__ == "__main__":
    sys.exit(main())
