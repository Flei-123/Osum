#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/kreuzecht.py -- DAS SCHLIESSKREUZ AUS DEM ECHTEN FENSTER.
#
#   python3 tools/design/kreuzecht.py <schirm.ppm>
#
# Justin sieht in der Titelleiste "-- [] /" statt "-- [] x": die zweite
# Diagonale fehlt. Auf meinem Belegbild aus der Zeichenroutine war das
# Kreuz vollstaendig. Also muss aus DEM Bild gemessen werden, das der
# Fensterserver wirklich malt.
#
# Das Werkzeug sucht die drei Knopffelder rechts in der Titelleiste,
# schneidet jedes einzeln aus und zaehlt je Zeile, wie viele Punkte
# LINKS und RECHTS der Mitte liegen. Ein Kreuz hat in fast jeder Zeile
# BEIDE; ein einzelner Schraegstrich hat nur eine Seite.
import sys


def ppm_lesen(p):
    d = open(p, 'rb').read()
    tok, i = [], 2
    while len(tok) < 3:
        while d[i:i + 1].isspace():
            i += 1
        if d[i:i + 1] == b'#':
            while d[i:i + 1] not in (b'\n', b''):
                i += 1
            continue
        j = i
        while not d[j:j + 1].isspace():
            j += 1
        tok.append(int(d[i:j])); i = j
    i += 1
    w, h, _ = tok
    return w, h, d[i:i + w * h * 3]


if __name__ == '__main__':
    w, h, px = ppm_lesen(sys.argv[1])

    def f(x, y):
        i = (y * w + x) * 3
        return (px[i], px[i + 1], px[i + 2])

    hg = f(5, 5)
    # Titelleiste des obersten Fensters finden
    ytop = None
    for y in range(0, h // 2):
        if sum(1 for x in range(w // 4, 3 * w // 4, 8) if f(x, y) != hg) > 50:
            ytop = y
            break
    xr = None
    for x in range(w - 1, w // 4, -1):
        if f(x, ytop + 6) != hg:
            xr = x
            break
    print("Titelleiste y=%d, rechte Fensterkante x=%d" % (ytop, xr))

    # Die drei Knopffelder: CAP_W0=30, uisc=2 -> je 60 breit,
    # unmittelbar links der Fensterkante.
    CAPW = 60
    for n, name in ((2, "SCHLIESSEN"), (1, "MAXIMIEREN"), (0, "MINIMIEREN")):
        x1 = xr - (2 - n) * CAPW
        x0 = x1 - CAPW
        # die hellsten Punkte im Feld = der Strich
        punkte = []
        for y in range(ytop, ytop + 60):
            for x in range(x0, x1):
                if 0 <= x < w and 0 <= y < h:
                    r, g, b = f(x, y)
                    if r + g + b > 330:
                        punkte.append((x, y))
        if not punkte:
            print("  %-11s KEIN Strich gefunden (x %d..%d)" % (name, x0, x1))
            continue
        xs = sorted(set(p[0] for p in punkte))
        ys = sorted(set(p[1] for p in punkte))
        mx = (xs[0] + xs[-1]) / 2.0
        beide = 0
        nur_links = 0
        nur_rechts = 0
        for y in ys:
            l = sum(1 for p in punkte if p[1] == y and p[0] < mx)
            r = sum(1 for p in punkte if p[1] == y and p[0] > mx)
            if l and r:
                beide += 1
            elif l:
                nur_links += 1
            elif r:
                nur_rechts += 1
        print("  %-11s %3d Punkte, %2dx%2d, Zeilen: beide %2d / nur links %2d / nur rechts %2d"
              % (name, len(punkte), xs[-1] - xs[0] + 1, ys[-1] - ys[0] + 1,
                 beide, nur_links, nur_rechts))
        if name == "SCHLIESSEN":
            if beide >= (len(ys) * 2) // 3:
                print("               -> ein KREUZ (beide Diagonalen)")
            else:
                print("               -> NUR EIN STRICH, die zweite Diagonale fehlt")
