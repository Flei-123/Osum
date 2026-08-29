#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/softui/gleich.py -- ZWEI BILDER, BILDPUNKT FUER BILDPUNKT.

    gleich.py <a.ppm> <b.ppm> [--karte <ziel.png>]

Die Gegenprobe, die diese Runde ueberhaupt landen laesst: `modern` darf
anders aussehen, `classic` nicht.  Das laesst sich nicht durch Nachdenken
feststellen -- die Runde hat den Fensterserver, die Widget-Bibliothek,
die Leiste und die Einstellungen angefasst -- also wird das Bild gegen
den Zweig gehalten, von dem abgezweigt wurde.

Ausgegeben wird die Zahl der abweichenden Bildpunkte, ihre groesste
Abweichung je Kanal und das umschliessende Rechteck.  Das Rechteck ist
der Teil, der einen Fehler suchbar macht: "1 738 Bildpunkte anders" sagt
nichts, "1 738 Bildpunkte anders, alle in 542,112 bis 632,131" sagt, dass
es die Fensterknoepfe sind.

`--karte` schreibt zusaetzlich ein Bild, in dem jeder abweichende Punkt
rot ist.  Mit `--zeit` wird die Uhr in der Taskleiste ausgenommen -- sie
zeigt die echte Zeit und ist zwischen zwei Laeufen zwangslaeufig
verschieden; das Rechteck dafuer wird angegeben und im Bericht genannt,
damit niemand es fuer eine stillschweigende Ausnahme haelt.
"""
import sys


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
    w, h, _ = f
    return w, h, d[at:at + w * h * 3]


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    W1, H1, a = ppm(argv[1])
    W2, H2, b = ppm(argv[2])
    if (W1, H1) != (W2, H2):
        print("gleich: verschiedene Groesse %dx%d gegen %dx%d"
              % (W1, H1, W2, H2))
        return 1
    aus = None
    aussen = []
    for i, v in enumerate(argv[3:]):
        if v == "--karte":
            aus = argv[3 + i + 1]
        if v == "--zeit":
            # Die Uhr rechts in der Leiste: x ab 740, unterste 28 Zeilen.
            aussen.append(("die Uhr", (740, H1 - 28, W1, H1)))
        if v == "--ausser":
            x, y, w, h = (int(t) for t in argv[3 + i + 1].split(","))
            aussen.append(("angegeben", (x, y, x + w, y + h)))
    n = 0
    mx = 0
    x0, y0, x1, y1 = W1, H1, -1, -1
    karte = bytearray(a) if aus else None
    for y in range(H1):
        row = y * W1 * 3
        for x in range(W1):
            o = row + x * 3
            if a[o] == b[o] and a[o + 1] == b[o + 1] and a[o + 2] == b[o + 2]:
                continue
            drin = False
            for _n, r in aussen:
                if r[0] <= x < r[2] and r[1] <= y < r[3]:
                    drin = True
                    break
            if drin:
                continue
            n += 1
            d = max(abs(a[o] - b[o]), abs(a[o + 1] - b[o + 1]),
                    abs(a[o + 2] - b[o + 2]))
            mx = max(mx, d)
            x0, y0 = min(x0, x), min(y0, y)
            x1, y1 = max(x1, x), max(y1, y)
            if karte is not None:
                karte[o] = 255
                karte[o + 1] = 0
                karte[o + 2] = 0
    if n == 0:
        print("gleich: unterschiedlich 0 von %d Bildpunkten -- IDENTISCH"
              % (W1 * H1))
    else:
        print("gleich: unterschiedlich %d von %d Bildpunkten (%.3f%%), "
              "groesste Abweichung %d, Rechteck %d,%d bis %d,%d"
              % (n, W1 * H1, 100.0 * n / (W1 * H1), mx, x0, y0, x1, y1))
    for nm, r in aussen:
        print("gleich: ausgenommen (%s) %d,%d bis %d,%d" % ((nm,) + r))
    if aus and karte is not None:
        from PIL import Image
        Image.frombytes("RGB", (W1, H1), bytes(karte)).save(aus)
        print("gleich: Karte nach %s" % aus)
    return 1 if n else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
