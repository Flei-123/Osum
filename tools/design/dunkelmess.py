#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/dunkelmess.py -- ZIEHT DER DUNKLE MODUS WIRKLICH MIT?
#
#   python3 tools/design/dunkelmess.py <hell.ppm> <dunkel.ppm> [name]
#
# Justins Frage war: "aendert der dunkle Modus auch die Farbe des
# Suchfensters?" Eine Behauptung genuegt dafuer nicht. Dieses Werkzeug
# vergleicht ZWEI Abzuege derselben Ansicht -- einmal hell, einmal
# dunkel -- und misst je Flaeche die mittlere Helligkeit.
#
#   Y = 0,299 R + 0,587 G + 0,114 B    (die uebliche Gewichtung; das
#                                       Auge sieht Gruen am hellsten)
#
# Eine Flaeche, die im dunklen Modus MITZIEHT, wird deutlich dunkler.
# Eine, die gleich hell bleibt, ist NICHT umgestellt -- und genau die
# will der Boss benannt haben.
#
# Untersucht werden nicht nur Mittelwerte ueber das ganze Bild (die
# verwischen alles), sondern ein RASTER aus Kacheln. So faellt auch
# eine einzelne Flaeche auf, die stehengeblieben ist, waehrend der
# Rest umschaltet.
import sys


def ppm_lesen(p):
    d = open(p, 'rb').read()
    if not d.startswith(b'P6'):
        raise SystemExit("kein P6-PPM: " + p)
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


def helligkeit(px, w, x0, y0, x1, y1, schritt=3):
    s = 0.0
    n = 0
    for y in range(y0, y1, schritt):
        for x in range(x0, x1, schritt):
            i = (y * w + x) * 3
            s += 0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2]
            n += 1
    return s / max(1, n)


if __name__ == '__main__':
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    hp, dp = sys.argv[1], sys.argv[2]
    name = sys.argv[3] if len(sys.argv) > 3 else hp.split('/')[-1]
    wh, hh, ph = ppm_lesen(hp)
    wd, hd, pd = ppm_lesen(dp)
    if (wh, hh) != (wd, hd):
        raise SystemExit("verschieden gross: %dx%d gegen %dx%d" % (wh, hh, wd, hd))

    gh = helligkeit(ph, wh, 0, 0, wh, hh)
    gd = helligkeit(pd, wd, 0, 0, wd, hd)
    print("== %s ==" % name)
    print("  ganzes Bild      hell %6.1f   dunkel %6.1f   Differenz %+7.1f  %s"
          % (gh, gd, gd - gh, "OK" if gd < gh - 20 else "<-- ZIEHT NICHT MIT"))

    # Das Raster: 8 x 6 Kacheln. Eine Kachel, die hell bleibt, waehrend
    # der Rest dunkel wird, ist der gesuchte Fehler.
    KX, KY = 8, 6
    stehen = []
    print()
    print("  Kachel        hell  dunkel   Diff")
    for ky in range(KY):
        zeile = []
        for kx in range(KX):
            x0, x1 = kx * wh // KX, (kx + 1) * wh // KX
            y0, y1 = ky * hh // KY, (ky + 1) * hh // KY
            a = helligkeit(ph, wh, x0, y0, x1, y1, 5)
            b = helligkeit(pd, wd, x0, y0, x1, y1, 5)
            zeile.append(b - a)
            if a > 60 and b > a - 20:
                stehen.append((kx, ky, a, b))
        print("   y%d  " % ky + " ".join("%+6.0f" % v for v in zeile))

    print()
    if stehen:
        print("  FLAECHEN, DIE NICHT MITZIEHEN (hell geblieben):")
        for kx, ky, a, b in stehen:
            print("    Kachel x%d y%d   hell %5.1f -> dunkel %5.1f  (%+.1f)"
                  % (kx, ky, a, b, b - a))
        sys.exit(1)
    print("  jede Kachel wird im dunklen Modus dunkler -- nichts stehengeblieben")
