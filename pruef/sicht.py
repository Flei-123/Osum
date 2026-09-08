#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""sicht.py -- EIN BILD IN ZAHLEN BESCHREIBEN.

    sicht.py beschreibe <png>              Farben, Flaechen, Zeilen mit Inhalt
    sicht.py vergleiche <a.png> <b.png>    was hat sich geaendert (Kaesten)
    sicht.py text <png> <wort> [px]        steht <wort> im Bild? (suchtext.py)

WARUM. Der Bericht dieser Runde darf nichts behaupten, was nicht
gemessen ist. "Das Fenster ist aufgegangen" ist eine Behauptung;
"in Kasten (300,200)-(700,500) haben sich 41 % der Bildpunkte
geaendert, neue Hauptfarbe #1b2836" ist ein Befund.
"""
import subprocess
import sys
from collections import Counter

REPO = "/root/osum-merge7"


def laden(p):
    from PIL import Image
    return Image.open(p).convert("RGB")


def hexf(t):
    return "#%02x%02x%02x" % t


def beschreibe(p):
    im = laden(p)
    w, h = im.size
    px = list(im.getdata())
    print("bild      %s  %dx%d" % (p, w, h))
    c = Counter(px)
    ges = len(px)
    print("farben    %d verschiedene" % len(c))
    for f, n in c.most_common(6):
        print("   %-9s %5.1f %%" % (hexf(f), 100.0 * n / ges))
    # Zeilen, die sich vom Hintergrund abheben: wo steht ueberhaupt was?
    haupt = c.most_common(1)[0][0]
    print("zeilen mit Inhalt (Anteil Nicht-Hauptfarbe je 20 Zeilen):")
    for y0 in range(0, h, 20):
        n = 0
        for y in range(y0, min(y0 + 20, h)):
            zeile = px[y * w:(y + 1) * w]
            n += sum(1 for q in zeile if q != haupt)
        a = 100.0 * n / (20.0 * w)
        if a > 1.0:
            print("   y=%4d..%4d  %5.1f %%" % (y0, min(y0 + 20, h) - 1, a))


def vergleiche(a, b):
    ia, ib = laden(a), laden(b)
    if ia.size != ib.size:
        print("verschiedene Groessen: %s vs %s" % (ia.size, ib.size))
        return 1
    w, h = ia.size
    pa, pb = list(ia.getdata()), list(ib.getdata())
    anders = [i for i in range(len(pa)) if pa[i] != pb[i]]
    print("bild a    %s" % a)
    print("bild b    %s" % b)
    print("geaendert %d von %d Bildpunkten (%.2f %%)"
          % (len(anders), len(pa), 100.0 * len(anders) / len(pa)))
    if not anders:
        print("KEIN EINZIGER BILDPUNKT ANDERS -- das Bild steht still.")
        return 0
    xs = [i % w for i in anders]
    ys = [i // w for i in anders]
    print("kasten    x=%d..%d  y=%d..%d" % (min(xs), max(xs), min(ys), max(ys)))
    nc = Counter(pb[i] for i in anders)
    print("neue Farben im geaenderten Bereich:")
    for f, n in nc.most_common(5):
        print("   %-9s %5.1f %%" % (hexf(f), 100.0 * n / len(anders)))
    return 0


def text(p, wort, px="15"):
    ppm = "/tmp/sicht-%d.ppm" % id(wort)
    laden(p).save(ppm)
    r = subprocess.run(["python3", REPO + "/tools/usbimg/suchtext.py", ppm,
                        REPO + "/assets/osum-sans.ttf", px, wort],
                       capture_output=True, text=True, cwd=REPO)
    print((r.stdout + r.stderr).strip())
    return r.returncode


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    k = sys.argv[1]
    if k == "beschreibe":
        beschreibe(sys.argv[2])
    elif k == "vergleiche":
        return vergleiche(sys.argv[2], sys.argv[3])
    elif k == "text":
        return text(sys.argv[2], sys.argv[3],
                    sys.argv[4] if len(sys.argv) > 4 else "15")
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
