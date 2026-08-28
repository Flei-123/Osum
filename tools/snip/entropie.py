#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/snip/entropie.py -- IST DER BEREICH WIRKLICH UNLESBAR?

    entropie.py <vorher.rgb> <nachher.rgb> <w> <h> <x0> <y0> <x1> <y1>
                [--blockmin N] [--kante-faktor F] [--entropie-faktor F]

"Verpixelt" ist eine Behauptung ueber ein Bild, und ein Bild kann man
nicht abstimmen lassen. Also wird gerechnet, und zwar zwei Zahlen, weil
EINE sich austricksen laesst:

  1. KANTENENERGIE. Die mittlere Summe der Betraege der waagerechten
     und senkrechten Nachbarunterschiede im Bereich. Text ist fast nur
     Kante -- schwarz gegen weiss, tausendmal je Zeile. Ein Mosaik
     laesst innerhalb eines Feldes GAR KEINE Kante uebrig, also faellt
     diese Zahl steil. Das ist die Zahl, die "unlesbar" am naechsten
     kommt: was keine Kanten hat, hat keine Buchstabenformen.
  2. ENTROPIE der Grauwerte in Bit je Bildpunkt (Shannon, ueber das
     Histogramm der 256 Stufen). Sie sagt, wie viel INFORMATION noch
     drinsteckt. Ein Mosaik senkt sie, weil aus vielen verschiedenen
     Werten wenige Mittelwerte werden.

WARUM BEIDE. Die Kantenenergie allein liesse sich mit einem
Weichzeichner druecken, ohne dass die Information weg waere -- und
Weichzeichnen ist laut Recherche TEILWEISE UMKEHRBAR, also gerade kein
Schutz. Die Entropie allein liesse sich mit einer Rasterung druecken,
die die Buchstaben noch erkennen laesst. Erst beide zusammen sagen
etwas.

  3. DIE DRITTE ZAHL, UND SIE IST DIE HARTE: wie viele VERSCHIEDENE
     Farben im Bereich uebrig sind. Ein Mosaik mit Feldkante 8 ueber
     einem Bereich von w*h Bildpunkten kann hoechstens
     ceil(w/8)*ceil(h/8) verschiedene Farben haben -- sind es mehr, ist
     der Bereich NICHT durchgaengig verpixelt, und zwar egal, wie gut
     die anderen beiden Zahlen aussehen. Das ist keine Statistik,
     sondern eine Schranke.

Ein Balken (Volltonflaeche) muss auf GENAU EINE Farbe kommen. Die
Recherche ist an dem Punkt eindeutig: ein Mosaik ist bei bekanntem
Zeichensatz rueckrechenbar, ein Volltonbalken nicht -- deshalb misst
dieses Skript beide Werkzeuge und nicht nur das huebschere.
"""
import math
import sys


def lade(pfad, w, h):
    roh = open(pfad, "rb").read()
    if len(roh) != w * h * 3:
        raise SystemExit("  FEHLER %s hat %d Oktette, erwartet %d"
                         % (pfad, len(roh), w * h * 3))
    return roh


def bereich(roh, w, x0, y0, x1, y1):
    grau = []
    farben = set()
    for y in range(y0, y1):
        z = (y * w + x0) * 3
        for x in range(x1 - x0):
            r, g, b = roh[z + x * 3], roh[z + x * 3 + 1], roh[z + x * 3 + 2]
            farben.add((r << 16) | (g << 8) | b)
            grau.append((r * 299 + g * 587 + b * 114) // 1000)
    return grau, farben


def kanten(grau, w, h):
    if w < 2 or h < 2:
        return 0.0
    s = 0
    n = 0
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if x + 1 < w:
                s += abs(grau[i] - grau[i + 1])
                n += 1
            if y + 1 < h:
                s += abs(grau[i] - grau[i + w])
                n += 1
    return s / float(n) if n else 0.0


def entropie(grau):
    hist = [0] * 256
    for v in grau:
        hist[v] += 1
    n = float(len(grau))
    e = 0.0
    for c in hist:
        if c:
            p = c / n
            e -= p * math.log(p, 2)
    return e


def main():
    if len(sys.argv) < 9:
        print(__doc__)
        return 2
    v_pfad, n_pfad = sys.argv[1], sys.argv[2]
    w, h, x0, y0, x1, y1 = (int(v) for v in sys.argv[3:9])
    blockmin = 0
    kf = 2.0
    ef = 1.2
    rest = sys.argv[9:]
    i = 0
    while i < len(rest):
        if rest[i] == "--blockmin":
            blockmin = int(rest[i + 1])
            i += 2
        elif rest[i] == "--kante-faktor":
            kf = float(rest[i + 1])
            i += 2
        elif rest[i] == "--entropie-faktor":
            ef = float(rest[i + 1])
            i += 2
        else:
            i += 1

    bw, bh = x1 - x0, y1 - y0
    gv, fv = bereich(lade(v_pfad, w, h), w, x0, y0, x1, y1)
    gn, fn = bereich(lade(n_pfad, w, h), w, x0, y0, x1, y1)
    kv, kn = kanten(gv, bw, bh), kanten(gn, bw, bh)
    ev, en = entropie(gv), entropie(gn)

    print("SNIP-REDAKTION: Bereich %d,%d bis %d,%d (%dx%d)"
          % (x0, y0, x1, y1, bw, bh))
    print("        Kantenenergie   vorher %7.3f   nachher %7.3f" % (kv, kn))
    print("        Entropie (Bit)  vorher %7.3f   nachher %7.3f" % (ev, en))
    print("        Farben          vorher %7d   nachher %7d"
          % (len(fv), len(fn)))

    schlecht = 0
    if kn * kf > kv:
        print("  FEHLER die Kantenenergie ist nicht um den Faktor %.1f "
              "gefallen" % kf)
        schlecht += 1
    else:
        print("  OK    die Kantenenergie faellt um Faktor %.1f"
              % (kv / kn if kn > 0.0001 else 9999.0))
    if en * ef > ev:
        print("  FEHLER die Entropie ist nicht um den Faktor %.1f gefallen"
              % ef)
        schlecht += 1
    else:
        print("  OK    die Entropie faellt von %.2f auf %.2f Bit" % (ev, en))
    if blockmin > 0:
        if len(fn) > blockmin:
            print("  FEHLER %d verschiedene Farben, hoechstens %d duerfen "
                  "es sein -- der Bereich ist nicht durchgaengig verpixelt"
                  % (len(fn), blockmin))
            schlecht += 1
        else:
            print("  OK    %d verschiedene Farben, die Schranke ist %d"
                  % (len(fn), blockmin))
    return 1 if schlecht else 0


if __name__ == "__main__":
    sys.exit(main())
