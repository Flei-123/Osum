#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/paint/shadow.py -- DER SCHATTEN UND DIE ECKE, AUS DEM BILD GELESEN.
#
# Die Regel dieser Runde ist die von Runde LOOK, eine Ebene tiefer:
# EINE AUSSAGE UEBER DEN BILDSCHIRM IST EINE AUSSAGE UEBER BILDPUNKTE,
# und sie ist nur etwas wert, wenn die Bildpunkte gezaehlt wurden.
# Nicht "das Fenster hat jetzt einen weichen Schatten" -- sondern
# "links neben dem Fenster bei y=240 liegen sechs Bildpunkte, deren
# Helligkeit von 231 auf 244 STEIGT, monoton, und ohne den Schatten
# stehen dort sechsmal 247."
#
# UND ES WIRD IMMER GEGEN DEN LAUF GEMESSEN, DER ES NICHT HAT.
#
# Die erste Fassung dieses Skripts las EINE Zeile aus EINEM Bild, fand
# links neben dem Fenster sieben Helligkeitsstufen und meldete gruen.
# Dieselben sieben Stufen standen im ALTEN Bild -- was sie gemessen
# hatte, war der Verlauf des Schreibtischhintergrunds.  Eine Messung,
# die nicht durchfallen kann, ist keine.  Also braucht jede Zusage hier
# ZWEI Bilder: `modern` und `classic`, gleiche Maschine, gleiches
# Fenster, ein Wort Unterschied auf der Platte.
#
#   ./tools/paint/shadow.py schatten <ohne.ppm> <mit.ppm> <x> <y> <w> <h>
#                                    [--reach N]
#       Rechts neben dem Fenster: wie viele Bildpunkte in `mit` DUNKLER
#       sind als in `ohne`, wie weit das reicht, und ob der Unterschied
#       zum Fenster hin monoton waechst.
#
#   ./tools/paint/shadow.py ecke <ohne.ppm> <mit.ppm> <x> <y> [--r N]
#       Das Eckquadrat: wie viele Bildpunkte darin eine Farbe tragen,
#       die WEDER die des Rahmens NOCH die des Grundes ist -- also
#       wirklich gemischt wurden.  In `ohne` muessen es null sein.
#
#   ./tools/paint/shadow.py vergleich <ohne.ppm> <mit.ppm> <x> <y> <w> <h>
#       Beide Laeufe gegeneinander: wie viele Bildpunkte sich
#       unterscheiden und wo.  Das ist die Gegenprobe -- ohne sie
#       koennte der "Schatten" der Schreibtischhintergrund sein.
import os
import sys


def ppm_lesen(pfad):
    with open(pfad, "rb") as fh:
        d = fh.read()
    if not d.startswith(b"P6"):
        raise SystemExit("%s ist kein P6-PPM" % pfad)
    felder = []
    i = 2
    while len(felder) < 3:
        while i < len(d) and d[i:i + 1].isspace():
            i += 1
        if d[i:i + 1] == b"#":
            while i < len(d) and d[i] != 0x0A:
                i += 1
            continue
        j = i
        while j < len(d) and not d[j:j + 1].isspace():
            j += 1
        felder.append(int(d[i:j]))
        i = j
    i += 1
    w, h, _mx = felder
    return w, h, d[i:i + w * h * 3]


def punkt(bild, w, h, x, y):
    if x < 0 or y < 0 or x >= w or y >= h:
        return None
    o = (y * w + x) * 3
    return (bild[o], bild[o + 1], bild[o + 2])


def hell(p):
    """Wahrgenommene Helligkeit -- Rec. 601, ganzzahlig."""
    return (p[0] * 299 + p[1] * 587 + p[2] * 114) // 1000


def schatten(argv):
    """Der Schatten, gegen den Lauf ohne ihn."""
    ohne, mit = argv[0], argv[1]
    x, y, w0, h0 = (int(v) for v in argv[2:6])
    reach = 6
    if "--reach" in argv:
        reach = int(argv[argv.index("--reach") + 1])
    wa, ha, A = ppm_lesen(ohne)
    wb, hb, B = ppm_lesen(mit)
    if (wa, ha) != (wb, hb):
        print("  FAIL  verschiedene Bildgroessen")
        return 1
    # RECHTS neben dem Fenster und nicht links: links kann ein anderes
    # Fenster liegen, dessen Inhalt sich zwischen zwei Laeufen ohnehin
    # unterscheidet (eine Shell schreibt eine Uhrzeit).  Rechts vom
    # obersten Fenster liegt der Schreibtisch, und der ist in beiden
    # Laeufen derselbe -- ausser dort, wo der Schatten liegt.
    zy = y + h0 // 2
    rand = x + w0
    print("PAINT-SCHATTEN: Fenster %d,%d %dx%d  Zeile y=%d  "
          "rechte Aussenkante x=%d" % (x, y, w0, h0, zy, rand - 1))
    ov = []
    mv = []
    for k in range(reach + 3):
        pa = punkt(A, wa, ha, rand + k, zy)
        pb = punkt(B, wb, hb, rand + k, zy)
        ov.append(None if pa is None else hell(pa))
        mv.append(None if pb is None else hell(pb))
    print("   ohne Schatten: %s"
          % " ".join("--" if v is None else "%3d" % v for v in ov))
    print("   mit  Schatten: %s"
          % " ".join("--" if v is None else "%3d" % v for v in mv))
    diff = [0 if (a is None or b is None) else a - b
            for a, b in zip(ov, mv)]
    print("   Unterschied:   %s" % " ".join("%3d" % d for d in diff))

    zusagen = 0
    fehler = 0
    # 1. Es gibt ueberhaupt einen Unterschied, und er ist DUNKLER.
    dunkler = sum(1 for d in diff if d > 0)
    if dunkler >= 3 and min(diff) >= 0:
        print("  OK    %d Bildpunkte sind dunkler als ohne Schatten, "
              "und keiner ist heller" % dunkler)
        zusagen += 1
    else:
        print("  FAIL  %d dunkler, kleinster Unterschied %d"
              % (dunkler, min(diff)))
        fehler += 1
    # 2. Er wird zum Fenster hin STAERKER -- ein Schatten, der nach
    #    aussen zunimmt, ist keiner.
    innen = diff[:dunkler] if dunkler else []
    monoton = all(innen[i] >= innen[i + 1] for i in range(len(innen) - 1))
    if monoton and innen:
        print("  OK    der Unterschied faellt nach aussen monoton "
              "(%d bis %d Helligkeitsstufen)" % (innen[0], innen[-1]))
        zusagen += 1
    else:
        print("  FAIL  der Unterschied ist nicht monoton: %s" % innen)
        fehler += 1
    # 3. Und er hoert auf. Ein Schatten, der bis zum Bildrand reicht,
    #    ist ein Farbfehler.
    if dunkler <= reach + 1 and (len(diff) > dunkler and diff[-1] == 0):
        print("  OK    er endet nach %d Bildpunkten (reach=%d) -- "
              "dahinter ist das Bild unveraendert" % (dunkler, reach))
        zusagen += 1
    else:
        print("  FAIL  er reicht %d Bildpunkte weit, erwartet hoechstens "
              "%d" % (dunkler, reach + 1))
        fehler += 1
    print("PAINT-SCHATTEN: %d Zusagen, %d Fehler" % (zusagen, fehler))
    return 1 if fehler else 0


def ecke(argv):
    """Die Ecke, gegen den Lauf mit der eckigen."""
    ohne, mit = argv[0], argv[1]
    x, y = int(argv[2]), int(argv[3])
    r = 8
    if "--r" in argv:
        r = int(argv[argv.index("--r") + 1])
    wa, ha, A = ppm_lesen(ohne)
    wb, hb, B = ppm_lesen(mit)

    def gemischt(b, w, h):
        """Bildpunkte im Eckquadrat, die WEDER Rahmen NOCH Grund sind.

        Die Rahmenfarbe wird tief im Fenster abgelesen (r, r hinter der
        Ecke), die Grundfarbe weit ausserhalb (drei Bildpunkte davor) --
        beide aus DEMSELBEN Bild, damit kein Schema-Unterschied
        hineinrechnet.
        """
        rahmen = punkt(b, w, h, x + r + 2, y + r + 2)
        grund = punkt(b, w, h, x - 3, y - 3)
        n = 0
        for dy in range(r):
            for dx in range(r):
                p = punkt(b, w, h, x + dx, y + dy)
                if p is None or p == rahmen or p == grund:
                    continue
                n += 1
        return n, rahmen, grund

    na, ra, ga = gemischt(A, wa, ha)
    nb, rb, gb = gemischt(B, wb, hb)
    print("PAINT-ECKE: Eckquadrat %dx%d bei %d,%d" % (r, r, x, y))
    print("   ohne Radius: %d gemischte Bildpunkte  (Rahmen %s, Grund %s)"
          % (na, ra, ga))
    print("   mit  Radius: %d gemischte Bildpunkte  (Rahmen %s, Grund %s)"
          % (nb, rb, gb))
    zusagen = 0
    fehler = 0
    if nb > na:
        print("  OK    die runde Ecke traegt %d gemischte Bildpunkte "
              "mehr als die eckige" % (nb - na))
        zusagen += 1
    else:
        print("  FAIL  die runde Ecke traegt nicht mehr gemischte "
              "Bildpunkte als die eckige (%d gegen %d)" % (nb, na))
        fehler += 1
    # DIE GEGENPROBE, und sie steht hier und nicht im Laeufer: `classic`
    # sagt Radius 0. Traegt sie trotzdem gemischte Bildpunkte, misst die
    # Zusage darueber nichts.
    if na * 4 < r * r:
        print("  OK    GEGENPROBE: die eckige Ecke ist zu weniger als "
              "einem Viertel gemischt (%d von %d)" % (na, r * r))
        zusagen += 1
    else:
        print("  FAIL  GEGENPROBE: auch die eckige Ecke ist gemischt "
              "(%d von %d)" % (na, r * r))
        fehler += 1
    print("PAINT-ECKE: %d Zusagen, %d Fehler" % (zusagen, fehler))
    return 1 if fehler else 0


def vergleich(argv):
    a, bpfad = argv[0], argv[1]
    x, y, w0, h0 = (int(v) for v in argv[2:6])
    wa, ha, ba = ppm_lesen(a)
    wb, hb, bb = ppm_lesen(bpfad)
    if (wa, ha) != (wb, hb):
        print("  FAIL  verschiedene Bildgroessen: %dx%d gegen %dx%d"
              % (wa, ha, wb, hb))
        return 1
    # Nur der RAND um das Fenster, nicht das Fenster selbst: dort steht
    # der Inhalt der Anwendung, und der darf sich aus hundert Gruenden
    # unterscheiden.
    reach = 8
    anders = 0
    gesamt = 0
    for yy in range(max(0, y - reach), min(ha, y + h0 + reach)):
        for xx in range(max(0, x - reach), min(wa, x + w0 + reach)):
            if x <= xx < x + w0 and y <= yy < y + h0:
                continue
            gesamt += 1
            if punkt(ba, wa, ha, xx, yy) != punkt(bb, wb, hb, xx, yy):
                anders += 1
    print("PAINT-VERGLEICH: Rand um %d,%d %dx%d (%d Bildpunkte breit)"
          % (x, y, w0, h0, reach))
    print("   %d von %d Bildpunkten unterscheiden sich (%.1f%%)"
          % (anders, gesamt, 100.0 * anders / gesamt if gesamt else 0))
    if anders > 0:
        print("  OK    der Rand ist nachweislich ein anderer")
        return 0
    print("  FAIL  die beiden Laeufe malen denselben Rand -- der "
          "Schatten ist nicht da")
    return 1


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    was = sys.argv[1]
    rest = sys.argv[2:]
    if was == "schatten":
        return schatten(rest)
    if was == "ecke":
        return ecke(rest)
    if was == "vergleich":
        return vergleich(rest)
    print("unbekannt: %s" % was)
    return 2


if __name__ == "__main__":
    sys.exit(main())
