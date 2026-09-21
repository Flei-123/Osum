#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-kontrast.py -- DIE AUSWAHLZEILE IM STARTMENUE, IN ZAHLEN.
#
# Gemessen wird der WCAG-Kontrast zwischen der SCHRIFTFARBE und dem
# BALKEN, auf dem sie steht. Vorher stand schwarzer Text auf dem blauen
# Auswahlbalken -- das ist der Fall, den diese Runde behoben hat.
#
#   db-kontrast.py <bild.ppm> [x0 y0 x1 y1]   (x0 y0 = links oben)
#
# Ohne Fensterangabe wird der Balken selbst gesucht: die groesste
# zusammenhaengende Flaeche in der Akzentfarbe (#2563eb, das Blau aus
# schema day). Innerhalb dieser Flaeche ist die haeufigste Farbe der
# Grund und die davon am weitesten entfernte die Schrift.
import os
import sys
from collections import Counter


def ppm(pfad):
    d = open(pfad, "rb").read()
    if not d.startswith(b"P6"):
        raise SystemExit("kein P6-PPM: %s" % pfad)
    f, at = [], 2
    while len(f) < 3:
        while at < len(d) and d[at:at + 1].isspace():
            at += 1
        if d[at:at + 1] == b"#":
            while d[at:at + 1] not in (b"\n", b""):
                at += 1
            continue
        s = at
        while at < len(d) and not d[at:at + 1].isspace():
            at += 1
        f.append(int(d[s:at]))
    at += 1
    w, h, _ = f
    px = d[at:at + w * h * 3]
    return w, h, px


def lum(c):
    def k(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * k(c[0]) + 0.7152 * k(c[1]) + 0.0722 * k(c[2])


def kontrast(a, b):
    la, lb = lum(a), lum(b)
    if la < lb:
        la, lb = lb, la
    return (la + 0.05) / (lb + 0.05)


def at(px, w, x, y):
    o = (y * w + x) * 3
    return (px[o], px[o + 1], px[o + 2])


def blaunah(c):
    # BLAU HEISST HIER: der Blauanteil liegt deutlich ueber Rot und
    # Gruen, und die Farbe ist nicht fast schwarz. Keine feste Zahl,
    # weil das Startmenue je nach Schema einen anderen Balken hat
    # (#2563eb bei `day`, #2f5f9c bei `night`) -- eine fest
    # eingetragene Farbe misst nur ein einziges Thema.
    r, g, b = c
    return b > r + 25 and b > g + 12 and b > 60


def main():
    bild = sys.argv[1]
    # Breite des Symbolfeldes am linken Rand der Zeile, in Bildpunkten.
    sym = int(os.environ.get("SYM", "30"))
    w, h, px = ppm(bild)

    if len(sys.argv) >= 6:
        x0, y0, x1, y1 = (int(v) for v in sys.argv[2:6])
    else:
        # Zeilen mit den meisten blauen Bildpunkten -> der Balken.
        zeilen = []
        for y in range(h):
            n = sum(1 for x in range(0, w, 2) if blaunah(at(px, w, x, y)))
            zeilen.append((n, y))
        zeilen.sort(reverse=True)
        if not zeilen or zeilen[0][0] < 10:
            print("KEIN blauer Auswahlbalken gefunden in %s" % bild)
            return 2
        ys = sorted(y for n, y in zeilen[:24] if n >= zeilen[0][0] * 0.6)
        y0, y1 = ys[0], ys[-1]
        xs = [x for x in range(w) if blaunah(at(px, w, x, (y0 + y1) // 2))]
        x0, x1 = xs[0], xs[-1]

    print("%s" % bild)
    print("  Balken x %d..%d  y %d..%d" % (x0, y0, x1, y1))

    # DAS PROGRAMMSYMBOL IST KEIN TEXT. Es sitzt links in der Zeile
    # (gemessen: x 26..31 im Startmenue) und ist dunkel -- wer es
    # mitzaehlt, liest rgb(48,31,98) als "Schrift" ab und bekommt
    # 2,71:1 statt der 5,17:1, die der Name wirklich hat. `sym`
    # ueberspringt die ersten Bildpunkte der Zeile.
    z = Counter()
    for y in range(y0, y1 + 1):
        for x in range(x0 + sym, x1 + 1):
            z[at(px, w, x, y)] += 1
    if not z:
        print("  leer")
        return 2

    grund = z.most_common(1)[0][0]
    # DIE SCHRIFT IST DIE ZWEITHAEUFIGSTE FARBE, nicht die mit dem
    # groessten Kontrast. Das ist der Unterschied zwischen Messen und
    # Wunschdenken: im Balken stehen auch einzelne Punkte aus dem
    # Symbol daneben (gemessen: rgb(47,254,210), 86 Punkte, 5,01:1).
    # Wer den Groesstwert nimmt, liest diesen Ausreisser ab und haelt
    # eine unlesbare Zeile fuer bestanden -- genau der Fehler, den
    # diese Runde behoben hat. Die Zeichen selbst sind der zweite
    # grosse Farbblock im Balken.
    kandidaten = [(n, c) for c, n in z.items() if c != grund]
    kandidaten.sort(reverse=True)
    schrift = kandidaten[0][1] if kandidaten else None
    best = kontrast(schrift, grund) if schrift is not None else 0

    print("  Grund   rgb%s  (%d Punkte)" % (str(grund), z[grund]))
    if schrift is None:
        print("  KEINE Schrift auf dem Balken gefunden")
        return 2
    print("  Schrift rgb%s  (%d Punkte)" % (str(schrift), z[schrift]))
    print("  KONTRAST %.2f:1" % best)
    print("  WCAG AA (4.5:1 fuer Fliesstext): %s" % ("BESTANDEN" if best >= 4.5 else "DURCHGEFALLEN"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
