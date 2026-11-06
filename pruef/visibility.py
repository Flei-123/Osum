#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    visibility.py -- EIN image IN numbers BESCHREIBEN.
    visibility.py beschreibe <png>              Farben, Flaechen, rows mit Inhalt
    visibility.py vergleiche <a.png> <b.png>    was hat sich geaendert (Kaesten)
    visibility.py text <png> <word> [px]        steht <word> im image? (searchtext.py)
"""
import subprocess
import sys
from collections import Counter

REPO = "/root/osum-merge7"


def loading(p):
    from PIL import Image
    return Image.open(p).convert("RGB")


def hexf(t):
    return "#%02x%02x%02x" % t


def beschreibe(p):
    im = loading(p)
    w, h = im.size
    px = list(im.getdata())
    print("bild      %s  %dx%d" % (p, w, h))
    c = Counter(px)
    ges = len(px)
    print("farben    %d verschiedene" % len(c))
    for f, n in c.most_common(6):
        print("   %-9s %5.1f %%" % (hexf(f), 100.0 * n / ges))
    # Zeilen, die sich vom Hintergrund abheben: wo steht ueberhaupt was?
    primary = c.most_common(1)[0][0]
    print("zeilen mit Inhalt (Anteil Nicht-Hauptfarbe je 20 Zeilen):")
    for y0 in range(0, h, 20):
        n = 0
        for y in range(y0, min(y0 + 20, h)):
            row = px[y * w:(y + 1) * w]
            n += sum(1 for q in row if q != primary)
        a = 100.0 * n / (20.0 * w)
        if a > 1.0:
            print("   y=%4d..%4d  %5.1f %%" % (y0, min(y0 + 20, h) - 1, a))


def vergleiche(a, b):
    ia, ib = loading(a), loading(b)
    if ia.size != ib.size:
        print("verschiedene Groessen: %s vs %s" % (ia.size, ib.size))
        return 1
    w, h = ia.size
    pa, pb = list(ia.getdata()), list(ib.getdata())
    different = [i for i in range(len(pa)) if pa[i] != pb[i]]
    print("bild a    %s" % a)
    print("bild b    %s" % b)
    print("geaendert %d von %d Bildpunkten (%.2f %%)"
          % (len(different), len(pa), 100.0 * len(different) / len(pa)))
    if not different:
        print("KEIN EINZIGER BILDPUNKT ANDERS -- das Bild steht still.")
        return 0
    xs = [i % w for i in different]
    ys = [i // w for i in different]
    print("kasten    x=%d..%d  y=%d..%d" % (min(xs), max(xs), min(ys), max(ys)))
    nc = Counter(pb[i] for i in different)
    print("neue Farben im geaenderten Bereich:")
    for f, n in nc.most_common(5):
        print("   %-9s %5.1f %%" % (hexf(f), 100.0 * n / len(different)))
    return 0


def text(p, word, px="15"):
    ppm = "/tmp/sicht-%d.ppm" % id(word)
    loading(p).save(ppm)
    r = subprocess.run(["python3", REPO + "/tools/usbimg/searchtext.py", ppm,
                        REPO + "/assets/osum-sans.ttf", px, word],
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
