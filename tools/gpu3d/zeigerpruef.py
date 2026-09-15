#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/gpu3d/zeigerpruef.py -- DER BILDBELEG DER RUNDE GPU (G-012).

    zeigerpruef.py <mit-hardware.ppm> <ohne-hardware.ppm>

WAS HIER BEWIESEN WIRD, UND WARUM GERADE SO.

`screendump vg` fotografiert die FLAECHE DES GERAETS -- also das, was
der Kern in die Ressource geschrieben hat. Die Zeigerflaeche legt der
Wirt erst BEIM ANZEIGEN darueber; im Foto der Flaeche ist sie nicht
enthalten. Daraus folgt eine Zusage, die man wirklich nachrechnen kann:

  * OHNE den neuen Weg malt `wm.compose` den Zeiger ins Bild.
    Im Foto stehen an seiner Stelle seine Farben -- dunkler Kern,
    weisser Rand.
  * MIT dem neuen Weg steht dort der GLATTE Schreibtischgrund.
    Der Zeiger ist aus dem Bild verschwunden, weil ihn das Geraet
    traegt.

Und weil beide Laeufe sonst identisch sind, muss der Unterschied
zwischen den Fotos GENAU EIN Rechteck in Zeigergroesse sein. Waere der
Zeiger in beiden Bildern drin, wuerde er doppelt gezeichnet; waere er
in keinem, wuerde gar nichts uebertragen. Beides faellt hier auf.

GEPRUEFT WIRD:
  1. Beide Fotos sind gleich gross (sonst vergleicht man Aepfel mit
     Birnen).
  2. Es gibt ueberhaupt einen Unterschied.
  3. Der Unterschied liegt in EINEM zusammenhaengenden Rechteck von
     Zeigergroesse (hoechstens 48x48 -- `cursor.MAXPX`).
  4. Im Softwarebild stehen dort WIRKLICH Zeigerfarben: dunkle UND
     helle Bildpunkte, jeweils ueber einer Mindestzahl.
  5. Im Hardwarebild ist dieselbe Stelle EINFARBIG -- dort ist nichts
     gemalt worden.

Rueckgabe 0, wenn alles stimmt; sonst 1 mit Begruendung.
"""
import sys

MAXPX = 48          # cursor.MAXPX -- groesser wird der Zeiger nie
MIN_DUNKEL = 20     # so viele Kernpunkte muss der gemalte Zeiger haben
MIN_HELL = 10       # und so viele Randpunkte


def lade(pfad):
    d = open(pfad, "rb").read()
    i = 0
    f = []
    while len(f) < 4:
        while i < len(d) and d[i:i + 1].isspace():
            i += 1
        if d[i:i + 1] == b"#":
            while i < len(d) and d[i:i + 1] != b"\n":
                i += 1
            continue
        j = i
        while j < len(d) and not d[j:j + 1].isspace():
            j += 1
        f.append(d[i:j])
        i = j
    i += 1
    if f[0] != b"P6":
        raise ValueError("%s ist kein P6-PPM" % pfad)
    w, h = int(f[1]), int(f[2])
    return w, h, d[i:i + w * h * 3]


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    try:
        wh, hh, hw = lade(sys.argv[1])
        ws, hs, sw = lade(sys.argv[2])
    except Exception as e:
        print("FEHL: %s" % e)
        return 1

    if (wh, hh) != (ws, hs):
        print("FEHL: die Fotos sind verschieden gross (%dx%d gegen %dx%d)"
              % (wh, hh, ws, hs))
        return 1
    w, h = wh, hh
    print("Groesse: %dx%d, beide gleich" % (w, h))

    diff = []
    for y in range(h):
        z = y * w * 3
        for x in range(w):
            o = z + x * 3
            if hw[o:o + 3] != sw[o:o + 3]:
                diff.append((x, y))

    if not diff:
        print("FEHL: die Fotos sind IDENTISCH -- dann hat der neue Weg")
        print("      nichts geaendert, und die Messung misst nichts.")
        return 1

    xs = [p[0] for p in diff]
    ys = [p[1] for p in diff]
    x0, x1 = min(xs), max(xs)
    y0, y1 = min(ys), max(ys)
    bw, bh = x1 - x0 + 1, y1 - y0 + 1
    print("Unterschied: %d Bildpunkte in x %d..%d, y %d..%d (%dx%d)"
          % (len(diff), x0, x1, y0, y1, bw, bh))

    if bw > MAXPX or bh > MAXPX:
        print("FEHL: der Unterschied ist groesser als ein Zeiger")
        print("      (%dx%d, hoechstens %dx%d erwartet) -- dann ist"
              % (bw, bh, MAXPX, MAXPX))
        print("      mehr verschieden als nur er.")
        return 1

    def punkte(buf):
        aus = []
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                o = (y * w + x) * 3
                aus.append(tuple(buf[o:o + 3]))
        return aus

    psw = punkte(sw)
    phw = punkte(hw)

    dunkel = sum(1 for p in psw if sum(p) < 120)
    hell = sum(1 for p in psw if sum(p) > 600)
    print("im Softwarebild an dieser Stelle: %d dunkle, %d helle Bildpunkte"
          % (dunkel, hell))
    if dunkel < MIN_DUNKEL or hell < MIN_HELL:
        print("FEHL: dort steht kein gemalter Zeiger (erwartet mindestens")
        print("      %d dunkle und %d helle)." % (MIN_DUNKEL, MIN_HELL))
        return 1

    farben = set(phw)
    print("im Hardwarebild an derselben Stelle: %d verschiedene Farben"
          % len(farben))
    if len(farben) != 1:
        print("FEHL: dort ist etwas gemalt -- mit Hardware-Zeiger muss die")
        print("      Stelle glatter Grund sein, sonst steht er DOPPELT.")
        for f in sorted(farben)[:6]:
            print("      %r" % (f,))
        return 1
    print("       und zwar einfarbig %r -- glatter Grund." % (phw[0],))

    print()
    print("BELEG: der Zeiger steht NUR im Softwarebild. Mit dem neuen Weg")
    print("       traegt ihn das Geraet, das Bild bleibt unberuehrt.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
