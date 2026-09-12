#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/protocol/schirmtext.py -- DEN TEXT AUS EINEM BILDSCHIRMFOTO LESEN.

WOZU. Die Abnahme dieser Runde verlangt einen Panik-Bildschirm "mit
mindestens fuenf aufgeloesten Symbolen und Datei:Zeile".  Ein Testlaeufer,
der nur zaehlt, wie viele Pixel nicht rot sind, misst das NICHT -- er
misst, dass irgendetwas gemalt wurde.  Und ein Testlaeufer, der statt des
Bildes die serielle Ausgabe liest, misst den ANDEREN Weg: gerade der
Panik-Bildschirm ist fuer die Maschine gebaut, die keine serielle Leitung
hat (Justins Brett meldet LSR 0xFF).

Also wird das Bild WIRKLICH GELESEN.  Das geht hier, weil der Schriftsatz
bekannt ist: `kernel/font.fi` traegt ihn als Oktettfolgen im Quelltext,
acht mal sechzehn Pixel je Zeichen, ein Bit je Pixel.  Dieses Programm

  1. holt die Glyphen aus `kernel/font.fi`,
  2. legt ueber das PPM ein Raster von 8x16,
  3. macht aus jeder Zelle wieder sechzehn Oktette (Pixel != Hintergrund
     -> Bit gesetzt),
  4. schlaegt die Oktettfolge in der Glyphentafel nach.

Das ist keine Zeichenerkennung mit Wahrscheinlichkeiten, sondern die
exakte Umkehrung des Zeichnens: entweder die Zelle IST das 'A' aus dem
Schriftsatz, oder sie ist es nicht.  Zellen, die zu keiner Glyphe passen,
werden zu '?' -- das faellt auf und wird nicht stillschweigend geraten.

Aufruf:
    python3 tools/protocol/schirmtext.py BILD.ppm [kernel/font.fi]
Ausgabe: der Text des Bildschirms, Zeile fuer Zeile, auf die Standardausgabe.
"""
import re
import sys

GLYPH_W = 8
GLYPH_H = 16
FIRST = 0x20
LAST = 0x7E


def glyphen(pfad):
    """Die Oktette aus den `b"..."`-Literalen von font.fi einsammeln.

    Sie stehen dort in `teil0`..`teilN`, jede in QUELLTEXTREIHENFOLGE
    hintereinander -- `font.load` setzt sie genau so zusammen.  Also
    reicht es, sie in der Reihenfolge des Vorkommens aneinanderzuhaengen.
    """
    text = open(pfad, encoding="utf-8", errors="surrogateescape").read()
    roh = bytearray()
    for m in re.finditer(r'b"((?:\\x[0-9a-fA-F]{2})+)"', text):
        for h in re.findall(r"\\x([0-9a-fA-F]{2})", m.group(1)):
            roh.append(int(h, 16))
    tafel = {}
    for c in range(FIRST, LAST + 1):
        i = (c - FIRST) * GLYPH_H
        if i + GLYPH_H > len(roh):
            break
        tafel.setdefault(bytes(roh[i:i + GLYPH_H]), chr(c))
    return tafel


def ppm_lesen(pfad):
    with open(pfad, "rb") as f:
        daten = f.read()
    if not daten.startswith(b"P6"):
        raise SystemExit("kein binaeres PPM (P6): " + pfad)
    felder = []
    i = 2
    while len(felder) < 3:
        while i < len(daten) and daten[i:i + 1].isspace():
            i += 1
        if daten[i:i + 1] == b"#":
            while daten[i:i + 1] not in (b"\n", b""):
                i += 1
            continue
        j = i
        while j < len(daten) and not daten[j:j + 1].isspace():
            j += 1
        felder.append(int(daten[i:j]))
        i = j
    i += 1
    w, h, _mx = felder
    return w, h, daten[i:i + w * h * 3]


def main():
    if len(sys.argv) < 2:
        sys.stderr.write(__doc__)
        return 1
    bild = sys.argv[1]
    font = sys.argv[2] if len(sys.argv) > 2 else "kernel/font.fi"
    tafel = glyphen(font)
    if not tafel:
        sys.stderr.write("schirmtext: kein Schriftsatz in " + font + "\n")
        return 1
    w, h, px = ppm_lesen(bild)

    def pixel(x, y):
        o = (y * w + x) * 3
        return (px[o], px[o + 1], px[o + 2])

    # DER HINTERGRUND IST DIE HAEUFIGSTE FARBE.  Das ist robuster als
    # eine feste Farbe im Skript: der Panik-Bildschirm ist rot, eine
    # gewoehnliche Textkonsole schwarz, und beides soll lesbar sein.
    zaehl = {}
    for y in range(0, h, 4):
        for x in range(0, w, 4):
            p = pixel(x, y)
            zaehl[p] = zaehl.get(p, 0) + 1
    hg = max(zaehl.items(), key=lambda kv: kv[1])[0]

    zeilen = []
    for zy in range(h // GLYPH_H):
        zeile = []
        for zx in range(w // GLYPH_W):
            muster = bytearray()
            for r in range(GLYPH_H):
                b = 0
                for c in range(GLYPH_W):
                    if pixel(zx * GLYPH_W + c, zy * GLYPH_H + r) != hg:
                        b |= 0x80 >> c
                muster.append(b)
            m = bytes(muster)
            if not any(m):
                zeile.append(" ")
            else:
                zeile.append(tafel.get(m, "?"))
        zeilen.append("".join(zeile).rstrip())
    while zeilen and not zeilen[-1]:
        zeilen.pop()
    for z in zeilen:
        print(z)
    return 0


if __name__ == "__main__":
    sys.exit(main())
