#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/kreuzmess.py -- DAS X AUS EINEM ECHTEN ABZUG, ZEILE FUER ZEILE.
#
#   python3 tools/design/kreuzmess.py <schirm.ppm> [x_rechte_kante]
#
# Der Boss hat die Bilder nachgemessen und in der ersten und letzten
# Zeile des Kreuzes rechts einen Bildpunkt vermisst (n=3 statt 4).
# Dieses Werkzeug macht genau diese Messung nachvollziehbar: es sucht
# den Schliessknopf im Abzug, zaehlt je Zeile die Strichpunkte und
# sagt, ob alle vier Enden gleich sind.
#
# Es misst am ECHTEN Bild -- dem, das der Kern bei 3440x1440 gemalt
# hat -- und nicht an einem Nachbau in Python.
import sys


def ppm_lesen(p):
    d = open(p, 'rb').read()
    if not d.startswith(b'P6'):
        raise SystemExit("kein P6-PPM")
    tok, i = [], 2
    while len(tok) < 3:
        while i < len(d) and d[i:i + 1].isspace():
            i += 1
        if d[i:i + 1] == b'#':
            while d[i:i + 1] not in (b'\n', b''):
                i += 1
            continue
        j = i
        while j < len(d) and not d[j:j + 1].isspace():
            j += 1
        tok.append(int(d[i:j])); i = j
    i += 1
    w, h, _ = tok
    return w, h, d[i:i + w * h * 3]


if __name__ == '__main__':
    src = sys.argv[1]
    w, h, px = ppm_lesen(src)

    def f(x, y):
        i = (y * w + x) * 3
        return (px[i], px[i + 1], px[i + 2])

    hg = f(5, 5)
    # Rechte Fensterkante in der Titelleiste finden.
    ytop = None
    for y in range(0, h // 2):
        if sum(1 for x in range(w // 4, 3 * w // 4, 8) if f(x, y) != hg) > 50:
            ytop = y
            break
    if ytop is None:
        raise SystemExit("kein Fenster gefunden")
    xr = None
    for x in range(w - 1, w // 4, -1):
        if f(x, ytop + 6) != hg:
            xr = x
            break
    if len(sys.argv) > 2:
        xr = int(sys.argv[2])
    print("Fenster: Titelleiste y=%d, rechte Kante x=%d" % (ytop, xr))

    # Der Schliessknopf ist der aeusserste rechts. Sein Feld grob
    # abstecken und die HELLEN Punkte (Strichfarbe) zaehlen: die
    # Knopfflaeche ist dunkel, der Strich hell.
    feld_x0, feld_x1 = xr - 60, xr - 5
    feld_y0, feld_y1 = ytop + 4, ytop + 52
    hell = []
    for y in range(feld_y0, feld_y1):
        for x in range(feld_x0, feld_x1):
            r, g, b = f(x, y)
            if r + g + b > 330:          # deutlich heller als die Flaeche
                hell.append((x, y))
    if not hell:
        raise SystemExit("kein Strich gefunden -- Feld falsch abgesteckt")
    xs = sorted(set(p[0] for p in hell))
    ys = sorted(set(p[1] for p in hell))
    print("Kreuz sitzt bei x %d..%d, y %d..%d  (%d x %d)"
          % (xs[0], xs[-1], ys[0], ys[-1], xs[-1] - xs[0] + 1,
             ys[-1] - ys[0] + 1))
    print()
    print("  Zeile   Punkte")
    zeilen = []
    for y in range(ys[0], ys[-1] + 1):
        n = sum(1 for p in hell if p[1] == y)
        zeilen.append(n)
        print("   %3d     %d" % (y - ys[0], n))
    print()
    spalten = [sum(1 for p in hell if p[0] == x) for x in range(xs[0], xs[-1] + 1)]
    print("erste Zeile %d, letzte Zeile %d   %s"
          % (zeilen[0], zeilen[-1],
             "GLEICH" if zeilen[0] == zeilen[-1] else "UNGLEICH <-- Fehler"))
    print("erste Spalte %d, letzte Spalte %d  %s"
          % (spalten[0], spalten[-1],
             "GLEICH" if spalten[0] == spalten[-1] else "UNGLEICH <-- Fehler"))
    gut = zeilen[0] == zeilen[-1] and spalten[0] == spalten[-1]
    print()
    print("URTEIL:", "alle vier Enden gleich" if gut else "die Enden sind NICHT gleich")
    sys.exit(0 if gut else 1)
