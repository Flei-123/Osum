#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/softui/kontrast.py -- DER KONTRAST, AUS DEM BILD GELESEN.

Die Auflage dieser Runde lautet: der Kontrast von Text auf Hintergrund
darf NICHT schlechter werden als heute (day+modern 5,16, night+modern
12,36).  Diese beiden Zahlen kommen aus dem TOKEN-MODELL --
`tools/theme/model.py contrast` rechnet sie aus den Farbdateien aus, und
5,16 ist dort das Paar `on-accent / accent`, also weisse Schrift auf dem
Akzentblau.  Das ist bis zu dieser Runde die Titelleiste jedes scharfen
Fensters.

DAS IST GENAU DER GRUND, WARUM DAS TOKENMODELL HIER NICHT REICHT.  Runde
SOFTUI nimmt der Titelleiste den Akzent (`tone=0`) -- die Farbpaare im
Modell bleiben Ziffer fuer Ziffer dieselben, aber auf dem Schirm steht
etwas anderes.  Wer nur das Modell nachrechnet, bekommt "unveraendert"
heraus und hat die Frage nicht beantwortet.

Also wird der Kontrast HIER AUS DEM BILD gemessen, an den Stellen, an
denen wirklich Schrift steht:

    kontrast.py band <bild.ppm> <x> <y> <w> <h>
        Der Kontrast der SCHRIFT in einem Rechteck gegen ihren GRUND.
        Grund = die haeufigste Farbe des Rechtecks.  Schrift = die
        Farbe mit dem groessten Abstand davon, die noch auf mindestens
        `--min` Bildpunkten steht (Voreinstellung 12) -- das schliesst
        die Zwischenstufen der Kantenglaettung aus, die per Definition
        weniger Kontrast haben und in keiner Richtlinie zaehlen.

    kontrast.py paar <rrggbb> <rrggbb>
        Zwei Farben, ohne Bild.

Die Rechnung ist WCAG 2.1, und sie ist bewusst die GLEITKOMMA-Fassung:
`kernel/user/wlibc.fi` rechnet in Festkomma, weil ein Kern kein
Gleitkomma haben will, und zwei unabhaengige Rechenwege sind hier der
ganze Sinn der Sache.  Wo die beiden sich um mehr als einen Hundertstel
unterscheiden, steht das im Bericht.
"""
import sys
from collections import Counter


def ppm(path):
    d = open(path, "rb").read()
    if not d.startswith(b"P6"):
        raise SystemExit("kein P6-PPM: %s" % path)
    f = []
    at = 2
    while len(f) < 3:
        while at < len(d) and d[at:at + 1].isspace():
            at += 1
        if d[at:at + 1] == b"#":
            while at < len(d) and d[at] != 0x0A:
                at += 1
            continue
        b = at
        while b < len(d) and not d[b:b + 1].isspace():
            b += 1
        f.append(int(d[at:b]))
        at = b
    at += 1
    w, h, _mx = f
    return w, h, d[at:at + w * h * 3]


def lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def lum(rgb):
    r, g, b = rgb
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def ratio(a, b):
    la, lb = lum(a), lum(b)
    if la < lb:
        la, lb = lb, la
    return (la + 0.05) / (lb + 0.05)


def band(path, x, y, w, h, minpx):
    W, H, px = ppm(path)
    if x < 0 or y < 0 or x + w > W or y + h > H:
        raise SystemExit("Rechteck liegt nicht im Bild (%dx%d)" % (W, H))
    cnt = Counter()
    for j in range(y, y + h):
        base = (j * W + x) * 3
        for i in range(w):
            o = base + i * 3
            cnt[(px[o], px[o + 1], px[o + 2])] += 1
    grund, gn = cnt.most_common(1)[0]
    best, bn, br = None, 0, 0.0
    for c, n in cnt.items():
        if n < minpx or c == grund:
            continue
        r = ratio(c, grund)
        if r > br:
            best, bn, br = c, n, r
    if best is None:
        print("kontrast: KEINE SCHRIFT gefunden -- grund #%02x%02x%02x "
              "auf %d von %d Bildpunkten" % (grund + (gn, w * h)))
        return 1
    print("kontrast: schrift #%02x%02x%02x (%d px)  grund #%02x%02x%02x "
          "(%d px)  ratio %.2f" % (best + (bn,) + grund + (gn, br)))
    return 0


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    if argv[1] == "paar" and len(argv) >= 4:
        def hx(s):
            v = int(s.lstrip("#"), 16)
            return ((v >> 16) & 255, (v >> 8) & 255, v & 255)
        print("kontrast: ratio %.2f" % ratio(hx(argv[2]), hx(argv[3])))
        return 0
    if argv[1] == "band" and len(argv) >= 7:
        mn = 12
        rest = argv[7:]
        if rest and rest[0].startswith("--min"):
            mn = int(rest[0].split("=")[1])
        return band(argv[2], int(argv[3]), int(argv[4]), int(argv[5]),
                    int(argv[6]), mn)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
