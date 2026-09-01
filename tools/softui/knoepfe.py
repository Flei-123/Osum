#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/softui/knoepfe.py -- DIE DREI FENSTERKNOEPFE, AUS DEM BILD.

Justin hat den WINDOWS-Stil verlangt und den macOS-Stil ausdruecklich
ausgeschlossen: keine drei bunten Kreise, sondern rechts oben ein
waagerechter Strich, ein Quadrat und ein Kreuz -- und beim Ueberfahren
eine dezente graue Flaeche, beim Schliessen eine ROTE mit weissem
Kreuz.

Das ist eine Aussage ueber Bildpunkte, also wird sie an Bildpunkten
geprueft und nicht an einer Zeile im Mitschnitt.  Das Programm rechnet
die Lage der drei Felder aus der `wm: win`-Zeile des scharfen Fensters
aus -- dieselbe Rechnung wie `kernel/wm.fi`, `cap_x0` -- und liest dann
das 10 x 10 grosse Zeichenfeld jedes Knopfes aus:

  min     genau EINE Zeile des Feldes traegt Tinte, und sie ist voll
  max     die vier Raender tragen Tinte, das Innere nicht
  close   beide Diagonalen tragen Tinte, die Mitte der Kanten nicht

  hover   im Feld des ueberfahrenen Schliessen-Knopfes ist die
          HAEUFIGSTE Farbe rot (mehr Rot als Gruen und Blau zusammen um
          einen deutlichen Abstand), und das Kreuz darauf ist hell
  macos   nirgends im Titelbalken steht ein Kreis: geprueft als "es gibt
          keine drei Flaechen von 8 bis 14 Bildpunkten Durchmesser in
          drei VERSCHIEDENEN gesaettigten Farben nebeneinander"

    knoepfe.py <bild.ppm> <serial.txt>
"""
import re
import sys
from collections import Counter

CAP_W = 30
CAP_N = 3
BORDER = 2
TITLE_H = 22


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


WIN = re.compile(r"^wm: win nr=(\d+) id=(\d+) .*x=(-?\d+) y=(-?\d+) "
                 r"w=(\d+) h=(\d+) focus=(\d+) .*ow=(\d+) oh=(\d+) t=\[(.*)\]$")


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    W, H, px = ppm(argv[1])

    def at(x, y):
        o = (y * W + x) * 3
        return (px[o], px[o + 1], px[o + 2])

    wins = []
    for ln in open(argv[2], "rb").read().decode("utf-8", "replace").splitlines():
        m = WIN.match(ln.strip())
        if m:
            wins.append(dict(x=int(m.group(3)), y=int(m.group(4)),
                             fok=int(m.group(7)), ow=int(m.group(8)),
                             oh=int(m.group(9)), t=m.group(10)))
    fok = [w for w in wins if w["fok"] == 1 and w["ow"] > 200]
    if not fok:
        print("kein scharfes Fenster im Mitschnitt")
        return 1
    w = fok[-1]
    bx = w["x"] + w["ow"] - BORDER - CAP_N * CAP_W
    by = w["y"] + BORDER
    h = TITLE_H - 1 - BORDER
    print("fenster '%s' bei %d,%d  knoepfe ab x=%d y=%d h=%d"
          % (w["t"], w["x"], w["y"], bx, by, h))
    gy = by + (h - 10) // 2
    felder = []
    for n in range(CAP_N):
        gx = bx + n * CAP_W + (CAP_W - 10) // 2
        grid = []
        for j in range(10):
            grid.append([at(gx + i, gy + j) for i in range(10)])
        felder.append((gx, gy, grid))

    def dunkel(c, grund):
        return (abs(c[0] - grund[0]) + abs(c[1] - grund[1])
                + abs(c[2] - grund[2])) > 90

    bad = 0
    # der Grund ist die haeufigste Farbe des ersten Feldes
    cnt = Counter()
    for row in felder[0][2]:
        for c in row:
            cnt[c] += 1
    grund = cnt.most_common(1)[0][0]

    # --- MIN: eine volle Zeile, sonst nichts
    g = felder[0][2]
    zeilen = [sum(1 for c in row if dunkel(c, grund)) for row in g]
    voll = [i for i, n in enumerate(zeilen) if n >= 9]
    leer = [i for i, n in enumerate(zeilen) if n == 0]
    if len(voll) == 1 and len(leer) == 9:
        print("min: strich ok  (zeile %d voll, neun leer)" % voll[0])
    else:
        print("min: KEIN strich -- zeilen %s" % zeilen)
        bad += 1

    # --- MAX: Rand voll, Mitte leer
    g = felder[1][2]
    rand = (sum(1 for c in g[0] if dunkel(c, grund))
            + sum(1 for c in g[9] if dunkel(c, grund))
            + sum(1 for j in range(1, 9) if dunkel(g[j][0], grund))
            + sum(1 for j in range(1, 9) if dunkel(g[j][9], grund)))
    mitte = sum(1 for j in range(1, 9) for i in range(1, 9)
                if dunkel(g[j][i], grund))
    if rand >= 32 and mitte == 0:
        print("max: quadrat ok  (rand %d von 36, inneres %d)" % (rand, mitte))
    else:
        print("max: KEIN quadrat -- rand %d, inneres %d" % (rand, mitte))
        bad += 1

    # --- CLOSE: zwei Diagonalen. Der Grund ist hier ein anderer, wenn
    #     der Knopf ueberfahren wird -- also eigener Zaehler.
    gx, gy, g = felder[2]
    cnt2 = Counter()
    for row in g:
        for c in row:
            cnt2[c] += 1
    grund2 = cnt2.most_common(1)[0][0]
    dia = sum(1 for k in range(10) if dunkel(g[k][k], grund2)) \
        + sum(1 for k in range(10) if dunkel(g[k][9 - k], grund2))
    kante = sum(1 for k in range(2, 8)
                if dunkel(g[0][k], grund2) or dunkel(g[9][k], grund2))
    if dia >= 18 and kante == 0:
        print("close: kreuz ok  (%d von 20 Diagonalpunkten, %d Kantenpunkte)"
              % (dia, kante))
    else:
        print("close: KEIN kreuz -- diagonalen %d, kanten %d" % (dia, kante))
        bad += 1

    # --- HOVER: die Flaeche des Schliessen-Knopfes ist rot
    fx = bx + 2 * CAP_W
    flaeche = Counter()
    for j in range(by, by + h):
        for i in range(fx, fx + CAP_W):
            flaeche[at(i, j)] += 1
    haupt, hn = flaeche.most_common(1)[0]
    r, gg, b = haupt
    rot = r > 120 and r > gg + 60 and r > b + 60
    if rot:
        hell = sum(1 for k in range(10)
                   if sum(g[k][k]) > sum(haupt) + 150)
        print("hover: rot ok  flaeche #%02x%02x%02x auf %d von %d punkten, "
              "kreuz hell auf %d von 10" % (r, gg, b, hn, CAP_W * h, hell))
        if hell < 6:
            print("hover: aber das Kreuz ist NICHT hell genug")
            bad += 1
    else:
        print("hover: die Flaeche ist NICHT rot (#%02x%02x%02x auf %d punkten)"
              % (r, gg, b, hn))
        bad += 1

    # --- MACOS-GEGENPROBE: keine drei gesaettigten Kreise nebeneinander
    # ES GEHT UM DEN FARBTON UND NICHT UM DIE FARBE. Die erste Fassung
    # hat gesaettigte Farben in Wuerfel von 32 Stufen einsortiert und
    # dann fuenf "Gruppen" gefunden -- alle fuenf waren das ROT des
    # ueberfahrenen Schliessen-Knopfes samt seiner Kantenglaettung. Ein
    # roter Knopf ist aber genau das, was diese Runde bauen SOLL; der
    # macOS-Stil ist ROT UND GELB UND GRUEN NEBENEINANDER. Also wird
    # nach FAMILIEN gezaehlt, sechs zu sechzig Grad, und mehr als eine
    # ist der Verdacht.
    fam = {}
    for j in range(by, by + h):
        for i in range(w["x"], w["x"] + w["ow"]):
            c = at(i, j)
            mx, mn = max(c), min(c)
            if mx > 110 and mx - mn > 70:
                r, g, b = (v / 255.0 for v in c)
                mxf, mnf = max(r, g, b), min(r, g, b)
                d = mxf - mnf
                if mxf == r:
                    hue = (60 * ((g - b) / d)) % 360
                elif mxf == g:
                    hue = 60 * ((b - r) / d) + 120
                else:
                    hue = 60 * ((r - g) / d) + 240
                fam[int(hue // 60)] = fam.get(int(hue // 60), 0) + 1
    stark = [k for k, n in fam.items() if n >= 40]
    if len(stark) <= 1:
        print("macos: keine kreise  (%d Farbfamilie(n) mit mehr als 40 "
              "Punkten im Balken: %s)" % (len(stark), sorted(stark)))
    else:
        print("macos: VERDACHT -- %d Farbfamilien im Balken: %s"
              % (len(stark), sorted((k, fam[k]) for k in stark)))
        bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
