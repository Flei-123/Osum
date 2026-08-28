#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/viewer/mkbilder.py -- die Testbilder DIESER Runde, und die
Vorlagen, gegen die gemessen wird.

Jedes Bild wird hier auf dem WIRT gebaut und daneben mit Pillow
dekodiert; die dekodierten Bildpunkte kommen als rohe RGBA-Datei auf
dasselbe Plattenabbild. `/bin/imgtest` dekodiert im System dieselbe
Datei und vergleicht Oktett fuer Oktett gegen die Vorlage.

WARUM PILLOW UND NICHT "SIEHT GUT AUS": Pillow ist libjpeg-turbo,
zlib-ng und giflib -- also genau die Umsetzungen, an denen sich jeder
Betrachter der Welt messen lassen muss. Ein eigener Dekodierer, der um
30 Stufen danebenliegt, sieht auf einem Foto voellig in Ordnung aus.

WARUM DIE VORLAGE FUER GROSSE BILDER ABGESCHNITTEN IST: ein Bild mit 12
Megabildpunkten waere als RGBA 48 Megaoktett. Die passen nicht auf ein
Abbild, das in einer Minute gebaut werden soll. Fuer die grossen Bilder
liegt deshalb nur der ANFANG als Vorlage da (Zeilenzahl in der Tabelle
unten), und `imgtest` vergleicht so viele Zeilen, wie die Vorlage
hergibt -- und sagt, wie viele es waren.

    python3 tools/viewer/mkbilder.py <zielverzeichnis>
"""

import os
import struct
import sys
import zlib

from PIL import Image, ImageDraw

# (Name, Zeilen der Vorlage)  --  0 = ganzes Bild
VORLAGE_ZEILEN = {}


def foto(w, h, seed=7):
    """Ein Bild mit dem, was einem Dekodierer wehtut: harte Kanten,
    weiche Verlaeufe, gesaettigte Farben und feine Streifen."""
    im = Image.new("RGB", (w, h))
    px = im.load()
    for y in range(h):
        for x in range(w):
            r = (x * 255) // max(w - 1, 1)
            g = (y * 255) // max(h - 1, 1)
            b = ((x + y) * seed) % 256
            px[x, y] = (r, g, b)
    d = ImageDraw.Draw(im)
    # harte Kanten: die schlimmste Stelle fuer die Farb-Unterabtastung
    d.rectangle([w // 8, h // 8, w // 3, h // 3], fill=(255, 0, 0))
    d.rectangle([w // 2, h // 6, w * 3 // 4, h // 2], fill=(0, 0, 255))
    d.ellipse([w // 3, h // 2, w * 2 // 3, h * 9 // 10], fill=(255, 255, 0))
    # feine Streifen: eine Stelle, an der Nearest-Verkleinerung sichtbar
    # falsch wird
    for x in range(0, w, 3):
        d.line([(x, 0), (x, h // 12)], fill=(255, 255, 255))
    d.line([(0, 0), (w - 1, h - 1)], fill=(0, 0, 0), width=2)
    return im


def schreib_ref(pfad, im, zeilen=0):
    """Die Vorlage: rohes RGBA, so wie `img.next_row` es liefert."""
    rgba = im.convert("RGBA")
    if zeilen and zeilen < rgba.height:
        rgba = rgba.crop((0, 0, rgba.width, zeilen))
    with open(pfad, "wb") as f:
        f.write(rgba.tobytes())


def main():
    ziel = sys.argv[1]
    os.makedirs(ziel, exist_ok=True)
    p = lambda n: os.path.join(ziel, n)
    liste = []

    def dazu(name, im, refzeilen=0, refim=None):
        """Die Vorlage kommt aus dem, was Pillow AUS DER DATEI liest --
        nicht aus dem Bild im Speicher. Nur so misst der Vergleich den
        Dekodierer und nicht den Encoder."""
        gelesen = Image.open(p(name))
        gelesen.load()
        schreib_ref(p(name + ".rgba"), refim if refim else gelesen, refzeilen)
        liste.append((name, gelesen.width, gelesen.height, refzeilen))

    # ------------------------------------------------------------ JPEG
    im = foto(64, 48)
    im.save(p("j444.jpg"), quality=92, subsampling=0)
    dazu("j444.jpg", im)
    im.save(p("j422.jpg"), quality=90, subsampling=1)
    dazu("j422.jpg", im)
    im.save(p("j420.jpg"), quality=85, subsampling=2)
    dazu("j420.jpg", im)
    im.convert("L").save(p("jgrau.jpg"), quality=88)
    dazu("jgrau.jpg", im)
    # Neustartmarken: ein kaputtes Stueck vergiftet den Rest nicht
    im.save(p("jrest.jpg"), quality=85, subsampling=2, restart_marker_blocks=4)
    dazu("jrest.jpg", im)
    # ungerade Masse: die MCU ragt ueber den Rand
    foto(37, 23, 11).save(p("jodd.jpg"), quality=90, subsampling=2)
    dazu("jodd.jpg", im)
    foto(1, 1, 3).save(p("j1x1.jpg"), quality=90)
    dazu("j1x1.jpg", im)
    foto(1, 129, 5).save(p("jschmal.jpg"), quality=90, subsampling=2)
    dazu("jschmal.jpg", im)
    # progressiv: MUSS abgelehnt werden, mit Namen
    im.save(p("jprog.jpg"), quality=85, progressive=True)
    liste.append(("jprog.jpg", im.width, im.height, -1))
    # EXIF-Ausrichtung 6 (90 Grad im Uhrzeigersinn)
    ex = Image.new("RGB", (40, 24), (10, 200, 60))
    d = ImageDraw.Draw(ex)
    d.rectangle([0, 0, 9, 5], fill=(255, 0, 0))
    exif = ex.getexif()
    exif[0x0112] = 6
    ex.save(p("jexif.jpg"), quality=95, subsampling=0, exif=exif)
    dazu("jexif.jpg", ex)
    # das grosse Bild: 12 Megabildpunkte, 4:2:0 -- die Zahl der Runde
    gross = foto(400, 300, 13).resize((4000, 3000), Image.BICUBIC)
    gross.save(p("j12mp.jpg"), quality=80, subsampling=2)
    dazu("j12mp.jpg", gross, refzeilen=24)
    # 50 Megabildpunkte: das Bild, das das System nicht umbringen darf
    riesig = foto(200, 156, 17).resize((8000, 6250), Image.BICUBIC)
    riesig.save(p("j50mp.jpg"), quality=70, subsampling=2)
    dazu("j50mp.jpg", riesig, refzeilen=8)
    del riesig
    del gross

    # ------------------------------------------------------------- PNG
    im = foto(64, 48, 5)
    im.save(p("prgb.png"))
    dazu("prgb.png", im)
    rgba = im.convert("RGBA")
    px = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            r, g, b, _ = px[x, y]
            px[x, y] = (r, g, b, (x * 4) % 256)
    rgba.save(p("palpha.png"))
    dazu("palpha.png", rgba)
    pal = im.convert("P", palette=Image.ADAPTIVE, colors=64)
    pal.save(p("ppal.png"))
    dazu("ppal.png", pal)
    pal.save(p("ptrns.png"), transparency=3)
    dazu("ptrns.png", pal)
    im.convert("L").save(p("pgrau8.png"))
    dazu("pgrau8.png", im)
    im.convert("1").save(p("pgrau1.png"))
    dazu("pgrau1.png", im)
    im.convert("L").resize((32, 24)).convert("I;16").save(p("pgrau16.png"))
    dazu("pgrau16.png", im)
    im.save(p("pilace.png"), interlace=True)
    dazu("pilace.png", im)
    # gross: 2000x1500 = 3 Megabildpunkte, RGB
    pg = foto(200, 150, 3).resize((2000, 1500), Image.NEAREST)
    pg.save(p("p3mp.png"))
    dazu("p3mp.png", pg, refzeilen=16)
    del pg

    # ------------------------------------------------------------- BMP
    im = foto(64, 48, 9)
    im.save(p("b24.bmp"))
    dazu("b24.bmp", im)
    im.convert("RGBA").save(p("b32.bmp"))
    dazu("b32.bmp", im)
    im.convert("P", palette=Image.ADAPTIVE, colors=256).save(p("b8.bmp"))
    dazu("b8.bmp", im)
    im.convert("1").save(p("b1.bmp"))
    dazu("b1.bmp", im)

    # ------------------------------------------------------------- GIF
    im.convert("P", palette=Image.ADAPTIVE, colors=128).save(p("gstill.gif"))
    dazu("gstill.gif", im)
    rahmen = []
    for k in range(4):
        f = Image.new("P", (48, 32))
        f.putpalette([0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255] + [0] * 756)
        dd = ImageDraw.Draw(f)
        dd.rectangle([0, 0, 47, 31], fill=0)
        dd.rectangle([k * 8, 4, k * 8 + 10, 20], fill=1 + (k % 3))
        rahmen.append(f)
    rahmen[0].save(p("ganim.gif"), save_all=True, append_images=rahmen[1:],
                   duration=120, loop=0, disposal=2)
    dazu("ganim.gif", rahmen[0])
    # verschraenktes GIF
    im.convert("P", palette=Image.ADAPTIVE, colors=64).save(
        p("gilace.gif"), interlace=True)
    dazu("gilace.gif", im)

    # ------------------------------------------- kaputte und halbe Dateien
    #
    # Sie haben keine Vorlage: die Zusage ist nicht "richtig dekodiert",
    # sondern "kein Absturz und ein Grund mit Namen".
    def kuerzen(quelle, ziel, anteil):
        b = open(p(quelle), "rb").read()
        open(p(ziel), "wb").write(b[: max(4, int(len(b) * anteil))])
        liste.append((ziel, 0, 0, -1))

    kuerzen("j420.jpg", "kurz.jpg", 0.55)
    kuerzen("prgb.png", "kurz.png", 0.45)
    kuerzen("ganim.gif", "kurz.gif", 0.5)
    kuerzen("b24.bmp", "kurz.bmp", 0.4)
    kuerzen("j420.jpg", "winzig.jpg", 0.01)

    # Umgedrehte Oktette in der Mitte: der Entropie-Dekodierer bekommt
    # Unsinn, der Prozess muss trotzdem leben.
    b = bytearray(open(p("j420.jpg"), "rb").read())
    for i in range(len(b) // 2, min(len(b) // 2 + 64, len(b))):
        b[i] = b[i] ^ 0x5A
    open(p("mues.jpg"), "wb").write(bytes(b))
    liste.append(("mues.jpg", 0, 0, -1))

    b = bytearray(open(p("prgb.png"), "rb").read())
    for i in range(60, min(120, len(b))):
        b[i] = (b[i] + 77) & 255
    open(p("mues.png"), "wb").write(bytes(b))
    liste.append(("mues.png", 0, 0, -1))

    # Eine Datei, die behauptet, riesig zu sein: 30000 x 30000 im Kopf,
    # aber nichts dahinter. Ein Dekodierer, der das glaubt, holt sich
    # 3,6 Gigaoktett.
    ihdr = struct.pack(">IIBBBBB", 30000, 30000, 8, 2, 0, 0, 0)
    roh = b"\x89PNG\r\n\x1a\n"
    roh += struct.pack(">I", 13) + b"IHDR" + ihdr
    roh += struct.pack(">I", zlib.crc32(b"IHDR" + ihdr))
    daten = zlib.compress(b"\x00" * 16)
    roh += struct.pack(">I", len(daten)) + b"IDAT" + daten
    roh += struct.pack(">I", zlib.crc32(b"IDAT" + daten))
    roh += struct.pack(">I", 0) + b"IEND" + struct.pack(">I",
                                                        zlib.crc32(b"IEND"))
    open(p("luege.png"), "wb").write(roh)
    liste.append(("luege.png", 0, 0, -1))

    # Formate, die dieses System NICHT kann und beim Namen nennen muss.
    foto(24, 16, 2).save(p("nein.webp"))
    liste.append(("nein.webp", 0, 0, -2))
    open(p("nein.svg"), "wb").write(
        b'<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
        b'<rect width="10" height="10"/></svg>')
    liste.append(("nein.svg", 0, 0, -2))
    foto(24, 16, 4).save(p("nein.tif"))
    liste.append(("nein.tif", 0, 0, -2))

    # Was auf dem Abbild landen soll, als Zeilen fuer die Shell.
    with open(p("LISTE"), "w") as f:
        for name, w, h, z in liste:
            f.write("%s %d %d %d\n" % (name, w, h, z))
    print("%d Dateien in %s" % (len(liste), ziel))


if __name__ == "__main__":
    main()
