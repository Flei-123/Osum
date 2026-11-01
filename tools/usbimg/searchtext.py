#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/usbimg/searchtext.py -- EINE ZEILE ECHTER SCHRIFT IM GANZEN BILD SUCHEN.

    searchtext.py <ppm> <ttf> <px> <text> [--tol N] [--min P] [--nicht]

WARUM ES DIESES WERKZEUG GIBT, obwohl `tools/gfx/checkshot.py` schon
`ttext` und `tkette` hat.

Die beiden dort brauchen die STELLE: x, Grundlinie, Vorder- und
Hintergrundfarbe. In `tools/i18n/run.sh` ist das richtig so -- das
Programm meldet die Lage seiner Bedienfelder selbst auf der seriellen
Leitung, und eine Zusage gegen eine gemeldete Koordinate ist staerker
als eine gegen eine gesuchte.

Auf dem USB-Stick gibt es diese Meldung nicht: dort laeuft der
Schreibtisch, wie Justin ihn startet, und nicht ein Messaufbau. Die
Frage dieser Runde ist auch eine andere und eine einfachere:

    STEHT DAS WORT MIT DEM UMLAUT IRGENDWO AUF DIESEM SCHIRM?

Also wird es gesucht. Der Ablauf:

  1. Die Zeile wird mit `tools/ttf/raster.py` gerastert -- der ZWEITEN
     Fassung des Rasterers aus `kernel/gfx/ttf.fi`, in einer anderen Sprache
     geschrieben. Es wird also nicht gegen sich selbst geprueft.
  2. Aus den Glyphen entsteht eine Liste von TINTENPUNKTEN
     (dx, dy, Deckung). Nur Punkte mit voller oder fast voller Deckung
     zaehlen (>= `--deckung`, Vorgabe 200 von 255): an einer halb
     gedeckten Kante haengt die Farbe am Untergrund, und der ist hier
     unbekannt.
  3. Fuer JEDE moegliche Lage im Bild wird gezaehlt, an wie vielen
     dieser Punkte wirklich Tinte steht -- "Tinte" heisst: der Punkt
     unterscheidet sich vom haeufigsten Wert seiner eigenen Umgebung
     nicht, sondern ist DERSELBE FARBWERT an allen Tintenstellen.
     Praktisch: die Lage gewinnt, an der die meisten Tintenpunkte
     dieselbe Farbe tragen UND sich diese Farbe von der an den
     Gegenpunkten unterscheidet.
  4. Ausgegeben wird die beste Lage und ihr Anteil in Prozent.

DIE GEGENPUNKTE SIND DER GRUND, WARUM DAS NICHT ZU LEICHT ZU HABEN IST.
Ohne sie wuerde jede einfarbige Flaeche jeden Text "finden": auf einem
weissen Rechteck tragen alle Tintenpunkte dieselbe Farbe. Also wird
zusaetzlich verlangt, dass die Punkte, an denen die Vorlage KEINE Tinte
hat (der Rand um jede Glyphe), sich von der Tintenfarbe unterscheiden.
Erst beides zusammen ist ein Buchstabe.

`--nicht` dreht die Bedingung um: dann ist ein FUND der Fehler. Damit
laesst sich messen, dass die ASCII-Ersatzschreibung ("Uebernehmen")
eben NICHT auf dem Schirm steht -- die Gegenprobe, ohne die der Fund
des richtigen Wortes nichts wert waere.

Rueckgabe 0, wenn die Bedingung erfuellt ist, sonst 1.
"""
import os
import sys

import numpy as np

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HIER, "..", "ttf"))
import raster  # noqa: E402


def ppm_read(path_2):
    roh = open(path_2, "rb").read()
    if not roh.startswith(b"P6"):
        raise ValueError("kein P6-PPM: %s" % path_2)
    felder = []
    i = 2
    while len(felder) < 3:
        while i < len(roh) and roh[i:i + 1].isspace():
            i += 1
        if roh[i:i + 1] == b"#":
            while i < len(roh) and roh[i] != 0x0A:
                i += 1
            continue
        j = i
        while j < len(roh) and not roh[j:j + 1].isspace():
            j += 1
        felder.append(int(roh[i:j]))
        i = j
    i += 1
    w, h, _ = felder
    d = np.frombuffer(roh[i:i + w * h * 3], dtype=np.uint8)
    return d.reshape(h, w, 3).astype(np.int16)


def points_2(text, ttf, px, deckung):
    """(dx, dy, tinte?) -- dy ist relativ zur Grundlinie."""
    if ttf.startswith("fui:"):
        import fuiraster
        s = fuiraster.Font_2(ttf[4:], px)
    else:
        s = raster.Font_2(ttf, px)
    voll = []
    rand = []
    for (c, x26) in s.stellen(text):
        g = s.glyphe(c)
        if g.w == 0 or g.h == 0:
            continue
        gx = x26 >> 6
        for r in range(g.h):
            for k in range(g.w):
                a = g.punkt(k, r)
                dx = gx + g.links + k
                dy = 0 - g.top_2 + r
                if a >= deckung:
                    voll.append((dx, dy))
                elif a == 0:
                    rand.append((dx, dy))
    return voll, rand, s


def search(image_2, voll, rand, tol):
    h, w, _ = image_2.shape
    xs = [p[0] for p in voll] + [p[0] for p in rand]
    ys = [p[1] for p in voll] + [p[1] for p in rand]
    x0, x1 = min(xs), max(xs)
    y0, y1 = min(ys), max(ys)
    bw = x1 - x0 + 1
    bh = y1 - y0 + 1
    if bw >= w or bh >= h:
        return None
    nx = w - bw + 1
    ny = h - bh + 1

    def area(dx, dy):
        ax = dx - x0
        ay = dy - y0
        return image_2[ay:ay + ny, ax:ax + nx, :]

    first = area(voll[0][0], voll[0][1])
    treffer = np.zeros((ny, nx), dtype=np.int32)
    for (dx, dy) in voll:
        f = area(dx, dy)
        eq = (np.abs(f - first) <= tol).all(axis=2)
        treffer += eq.astype(np.int32)
    gegen = np.zeros((ny, nx), dtype=np.int32)
    schritt = max(1, len(rand) // 400)
    genommen = rand[::schritt]
    for (dx, dy) in genommen:
        f = area(dx, dy)
        changed = (np.abs(f - first) > tol).any(axis=2)
        gegen += changed.astype(np.int32)

    anteil_tinte = treffer / float(len(voll))
    anteil_gegen = gegen / float(max(1, len(genommen)))
    punktzahl = np.minimum(anteil_tinte, anteil_gegen)
    idx = int(np.argmax(punktzahl))
    yy, xx = divmod(idx, nx)
    return (xx - x0, yy - y0, float(anteil_tinte[yy, xx]),
            float(anteil_gegen[yy, xx]), float(punktzahl[yy, xx]),
            len(voll), len(genommen))


def main(argv):
    if len(argv) < 5:
        print(__doc__)
        return 2
    ppm, ttf, px, text = argv[1], argv[2], int(argv[3]), argv[4]
    tol = 12
    mind = 0.97
    deckung = 255
    nicht = "--nicht" in argv
    for i, a in enumerate(argv):
        if a == "--tol":
            tol = int(argv[i + 1])
        if a == "--min":
            mind = float(argv[i + 1])
        if a == "--deckung":
            deckung = int(argv[i + 1])
    image_2 = ppm_read(ppm)
    voll, rand, _ = points_2(text, ttf, px, deckung)
    if not voll:
        print("die Zeile '%s' hat keinen einzigen vollgedeckten Punkt" % text)
        return 2
    e = search(image_2, voll, rand, tol)
    if e is None:
        print("the line is larger than the image")
        return 2
    x, y, at, ag, p, nv, ng = e
    wie = ("'%s' bei x=%d Grundlinie=%d: %d%% der %d Tintenpunkte, "
           "%d%% der %d Gegenpunkte" %
           (text, x, y, round(at * 100), nv, round(ag * 100), ng))
    if nicht:
        if p >= mind:
            print("FOUND although it must NOT be there -- %s" % wie)
            return 1
        print("not found (best value %d%%) -- %s" % (round(p * 100), wie))
        return 0
    if p >= mind:
        print(wie)
        return 0
    print("NOT found (best value %d%%) -- %s" % (round(p * 100), wie))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
