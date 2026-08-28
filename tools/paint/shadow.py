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
#   ./tools/paint/shadow.py schatten <ppm> <x> <y> <w> <h> [--reach N]
#       Der Verlauf links neben dem Fenster: wie viele verschiedene
#       Werte, ob er monoton zum Fenster hin dunkler wird, und wie weit
#       er reicht.
#
#   ./tools/paint/shadow.py ecke <ppm> <x> <y> [--r N]
#       Die obere linke Ecke des Fensters: wie viele Graustufen liegen
#       auf der Diagonale zwischen Rahmen und Grund.  Eine harte Ecke
#       hat ZWEI.
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
    pfad = argv[0]
    x, y, w0, h0 = (int(v) for v in argv[1:5])
    reach = 6
    if "--reach" in argv:
        reach = int(argv[argv.index("--reach") + 1])
    w, h, b = ppm_lesen(pfad)
    zy = y + h0 // 2
    werte = []
    for k in range(reach + 2, 0, -1):
        p = punkt(b, w, h, x - k, zy)
        werte.append(None if p is None else hell(p))
    print("PAINT-SCHATTEN: %s  Fenster %d,%d %dx%d  Zeile y=%d"
          % (os.path.basename(pfad), x, y, w0, h0, zy))
    print("   links davon, von aussen nach innen: %s"
          % " ".join("--" if v is None else str(v) for v in werte))
    echt = [v for v in werte if v is not None]
    stufen = len(set(echt))
    # Monoton FALLEND nach innen heisst: je naeher am Fenster, desto
    # dunkler.  Gleiche Werte sind erlaubt (der aeusserste Ring kann
    # rechnerisch bei Deckung 0 landen), Umkehrungen nicht.
    monoton = all(echt[i] >= echt[i + 1] for i in range(len(echt) - 1))
    tiefe = 0
    if echt:
        tiefe = echt[0] - min(echt)
    print("   verschiedene Werte=%d  monoton nach innen dunkler=%s  "
          "Tiefe=%d Helligkeitsstufen" % (stufen, "ja" if monoton else "NEIN",
                                          tiefe))
    zusagen = 0
    fehler = 0
    if stufen >= 3:
        print("  OK    der Verlauf traegt %d verschiedene Werte "
              "(eine harte Kante haette zwei)" % stufen)
        zusagen += 1
    else:
        print("  FAIL  nur %d verschiedene Werte -- das ist keine "
              "Mischung, das ist eine Kante" % stufen)
        fehler += 1
    if monoton:
        print("  OK    er wird zum Fenster hin monoton dunkler")
        zusagen += 1
    else:
        print("  FAIL  der Verlauf ist nicht monoton -- %s" % echt)
        fehler += 1
    print("PAINT-SCHATTEN: %d Zusagen, %d Fehler" % (zusagen, fehler))
    return 1 if fehler else 0


def ecke(argv):
    pfad = argv[0]
    x, y = int(argv[1]), int(argv[2])
    r = 8
    if "--r" in argv:
        r = int(argv[argv.index("--r") + 1])
    w, h, b = ppm_lesen(pfad)
    # Die Diagonale durch die obere linke Ecke.  Bei einer eckigen Ecke
    # springt sie in EINEM Schritt von Grund auf Rahmen.
    werte = []
    for k in range(r + 2):
        p = punkt(b, w, h, x + k, y + k)
        werte.append(None if p is None else hell(p))
    echt = [v for v in werte if v is not None]
    stufen = len(set(echt))
    print("PAINT-ECKE: %s  Ecke bei %d,%d  Radius erwartet %d"
          % (os.path.basename(pfad), x, y, r))
    print("   Diagonale: %s" % " ".join(str(v) for v in echt))
    print("   verschiedene Werte=%d" % stufen)
    if stufen >= 3:
        print("  OK    die Ecke traegt %d Stufen -- sie ist gerundet "
              "und geglaettet" % stufen)
        return 0
    print("  FAIL  die Ecke traegt %d Stufen -- sie ist hart" % stufen)
    return 1


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
