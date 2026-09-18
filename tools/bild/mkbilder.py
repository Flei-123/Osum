#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/bild/mkbilder.py -- DIE TESTBILDER DER RUNDE BILD.

    python3 tools/bild/mkbilder.py <zielverzeichnis>

Jedes Bild wird hier auf dem WIRT mit Pillow gebaut. Pillow ist
libjpeg-turbo, zlib-ng und giflib -- also genau die Umsetzungen, an
denen sich jeder Betrachter der Welt messen lassen muss.

WARUM NICHT "SIEHT GUT AUS": ein eigener Dekodierer, der um dreissig
Stufen danebenliegt, sieht auf einem Foto voellig in Ordnung aus. Nur
der Vergleich mit einer fremden Umsetzung faellt darauf nicht herein --
darum entstehen hier die Dateien, und `tools/alltag/bildref.py`
vergleicht danach Zahl gegen Zahl.

DIE AUSWAHL IST NICHT ZUFAELLIG. Jedes Bild steht fuer einen Weg im
Dekodierer, der sonst nie gegangen wird:

  g-einfarb    die kuerzeste LZW-Folge, die es gibt (ein Lauf)
  g-tafel      eine Farbtafel mit 256 Eintraegen -- misst, ob Index
               und Farbe zusammenpassen
  g-transp     ein durchsichtiger Index; was darunter liegt, bleibt
  g-lace       VERSCHACHTELT. Ein Leser, der das nicht kennt, malt die
               Zeilen an die falsche Stelle -- und das sieht nicht
               kaputt aus, nur falsch. Ohne Gegenprobe faellt es
               niemandem auf.
  g-anim       eine Bildfolge. Der Betrachter muss das ERSTE Vollbild
               zeigen und sagen, wie viele es sind.
  g-gross      breiter, als das LZW-Woerterbuch lang wird: erzwingt
               mindestens einen Loeschcode mitten im Bild.
  g-87a        die alte Fassung ohne Steuerbloecke
  b-*          PNG und BMP, die schon gingen -- als Nachweis, dass
               diese Runde sie nicht kaputtgemacht hat
  b-voll.jpg   JPEG 4:4:4, damit der Vergleich bildpunktweise sein darf
"""

import os
import sys

from PIL import Image, ImageDraw


def foto(w, h, seed=7):
    """Was einem Dekodierer wehtut: harte Kanten, weiche Verlaeufe,
    gesaettigte Farben."""
    im = Image.new("RGB", (w, h))
    px = im.load()
    for y in range(h):
        for x in range(w):
            r = (x * 255) // max(w - 1, 1)
            g = (y * 255) // max(h - 1, 1)
            b = ((x + y) * seed) % 256
            px[x, y] = (r, g, b)
    d = ImageDraw.Draw(im)
    d.rectangle([w // 8, h // 8, w // 3, h // 3], fill=(255, 0, 0))
    d.rectangle([w // 2, h // 6, w * 3 // 4, h // 2], fill=(0, 0, 255))
    d.ellipse([w // 3, h // 2, w * 2 // 3, h * 9 // 10], fill=(255, 255, 0))
    d.line([(0, 0), (w - 1, h - 1)], fill=(0, 0, 0), width=2)
    return im


def bunt_palette(w, h, n=256):
    """Ein Bild mit einer vollen Farbtafel: jeder Index kommt vor."""
    im = Image.new("P", (w, h))
    tafel = []
    for i in range(n):
        tafel += [(i * 7) % 256, (i * 13) % 256, (i * 29) % 256]
    tafel += [0, 0, 0] * (256 - n)
    im.putpalette(tafel)
    px = im.load()
    for y in range(h):
        for x in range(w):
            px[x, y] = ((x + y * 3) % n)
    return im


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    ziel = sys.argv[1]
    os.makedirs(ziel, exist_ok=True)
    p = lambda n: os.path.join(ziel, n)
    gemacht = []

    def sag(name, extra=""):
        gr = os.path.getsize(p(name))
        gemacht.append(name)
        print("%-16s %7d Oktette  %s" % (name, gr, extra))

    # ---------------------------------------------------------- GIF
    im = Image.new("P", (32, 24))
    im.putpalette([0, 0, 0, 220, 30, 40] + [0] * 762)
    for y in range(24):
        for x in range(32):
            im.putpixel((x, y), 1)
    im.save(p("g-einfarb.gif"))
    sag("g-einfarb.gif", "32x24, ein Lauf")

    im = bunt_palette(40, 30, 256)
    im.save(p("g-tafel.gif"))
    sag("g-tafel.gif", "40x30, 256 Farben")

    im = Image.new("P", (32, 32))
    im.putpalette([0, 0, 0, 255, 255, 255, 20, 200, 90] + [0] * 759)
    for y in range(32):
        for x in range(32):
            im.putpixel((x, y), 2 if (x // 4 + y // 4) % 2 else 1)
    im.save(p("g-transp.gif"), transparency=0)
    sag("g-transp.gif", "32x32, Index 0 durchsichtig")

    im = bunt_palette(64, 48, 64)
    im.save(p("g-lace.gif"), interlace=True)
    sag("g-lace.gif", "64x48, verschachtelt")

    # AUSDRUECKLICH NICHT VERSCHACHTELT. Pillow setzt das Merkmal von
    # sich aus bei fast jedem Bild -- ohne diese Datei wuerde der
    # gerade Weg (Zeile fuer Zeile) NIE gemessen, und ein Fehler darin
    # bliebe unentdeckt.
    im = bunt_palette(36, 28, 32)
    im.save(p("g-gerade.gif"), interlace=False)
    sag("g-gerade.gif", "36x28, NICHT verschachtelt")

    rahmen = []
    for k in range(4):
        f = Image.new("P", (48, 32))
        f.putpalette([0, 0, 0, 240, 60, 20, 30, 90, 240, 250, 240, 60]
                     + [0] * 756)
        for y in range(32):
            for x in range(48):
                f.putpixel((x, y), 1 + ((x // 8 + y // 8 + k) % 3))
        rahmen.append(f)
    rahmen[0].save(p("g-anim.gif"), save_all=True,
                   append_images=rahmen[1:], duration=120, loop=0)
    sag("g-anim.gif", "48x32, 4 Teilbilder")

    im = bunt_palette(160, 120, 256)
    im.save(p("g-gross.gif"))
    sag("g-gross.gif", "160x120, erzwingt Woerterbuchloeschung")

    im = Image.new("P", (24, 16))
    im.putpalette([10, 20, 30, 200, 200, 10] + [0] * 762)
    for y in range(16):
        for x in range(24):
            im.putpixel((x, y), 1 if x % 3 else 0)
    im.save(p("g-87a.gif"), version="GIF87a")
    sag("g-87a.gif", "24x16, GIF87a")

    # ---------------------------------------------------- PNG und BMP
    foto(48, 36).save(p("b-probe.png"))
    sag("b-probe.png", "48x36 RGB")
    foto(40, 30).save(p("b-probe.bmp"))
    sag("b-probe.bmp", "40x30 BMP 24 Bit")
    bunt_palette(32, 24, 128).convert("RGB").save(p("b-pal.png"))
    sag("b-pal.png", "32x24 aus Farbtafel")

    # ------------------------------------------------------------ JPEG
    foto(64, 48).save(p("b-voll.jpg"), quality=92, subsampling=0)
    sag("b-voll.jpg", "64x48 4:4:4")

    with open(p("liste.txt"), "w") as f:
        f.write("\n".join(gemacht) + "\n")
    print("mkbilder: %d Dateien" % len(gemacht))
    return 0


if __name__ == "__main__":
    sys.exit(main())
