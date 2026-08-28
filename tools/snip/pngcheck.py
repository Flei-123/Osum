#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/snip/pngcheck.py -- EIN PNG WIRKLICH LESEN, nicht nur ansehen.

    pngcheck.py <datei.png> [--raw <ziel.rgb>] [--still]

"Die Datei existiert" ist keine Messung, und "ein Betrachter zeigt etwas"
auch nicht -- ein Betrachter repariert stillschweigend, was er kann.
Dieses Skript ist ein STRENGER Leser: es prueft jedes Oktett des
Behaelters und steigt beim ersten Fehler aus.

    * die acht Oktette der Signatur
    * jeden Chunk: Laenge, Typ, CRC-32 ueber Typ UND Daten
    * IHDR: Breite, Hoehe, Bittiefe, Farbart, die drei Nullen
    * die Reihenfolge -- IHDR zuerst, IEND zuletzt, IDAT zusammenhaengend
    * dass hinter IEND NICHTS mehr steht (die Acropalypse-Falle,
      CVE-2023-21036: eine Datei, die beim Ueberschreiben nicht gekuerzt
      wurde, traegt dort die Reste des groesseren Originals)
    * den zlib-Strom samt Kopfpruefung (durch 31 teilbar) und ADLER-32
    * die Zeilenfilter 0..4, alle fuenf, zurueckgerechnet nach RFC 2083

Es haengt an `zlib` und `struct` aus der Standardbibliothek und an
sonst nichts -- dieselbe Regel wie `tools/gfx/ppm2png.py`: ein
Testlaeufer, der ohne Netz nicht durchlaeuft, ist kein Testlaeufer.

`--raw` schreibt das entpackte Bild als w*h*3 Oktette heraus, damit
`tools/snip/pixel.py` es gegen den Rahmenpuffer halten kann.
`--still` gibt nur den Beendigungscode.
"""
import binascii
import struct
import sys
import zlib

SIG = b"\x89PNG\r\n\x1a\n"


class Kaputt(Exception):
    pass


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def lies(pfad):
    roh = open(pfad, "rb").read()
    if len(roh) < 8 or roh[:8] != SIG:
        raise Kaputt("die Signatur stimmt nicht")
    at = 8
    ihdr = None
    idat = []
    gesehen = []
    idat_zusammen = True
    idat_fertig = False
    while True:
        if at + 8 > len(roh):
            raise Kaputt("die Datei endet mitten in einem Chunkkopf")
        (laenge,) = struct.unpack(">I", roh[at:at + 4])
        typ = roh[at + 4:at + 8]
        if at + 12 + laenge > len(roh):
            raise Kaputt("Chunk %s sagt %d Oktette, so viel ist nicht da"
                         % (typ.decode("latin1"), laenge))
        daten = roh[at + 8:at + 8 + laenge]
        (crc,) = struct.unpack(">I", roh[at + 8 + laenge:at + 12 + laenge])
        soll = binascii.crc32(typ + daten) & 0xFFFFFFFF
        if crc != soll:
            raise Kaputt("CRC von %s: Datei sagt %08X, gerechnet %08X"
                         % (typ.decode("latin1"), crc, soll))
        gesehen.append(typ)
        if typ == b"IHDR":
            if len(gesehen) != 1:
                raise Kaputt("IHDR ist nicht der erste Chunk")
            if laenge != 13:
                raise Kaputt("IHDR ist %d statt 13 Oktette" % laenge)
            ihdr = struct.unpack(">IIBBBBB", daten)
        elif typ == b"IDAT":
            if ihdr is None:
                raise Kaputt("IDAT vor IHDR")
            if idat_fertig:
                idat_zusammen = False
            idat.append(daten)
        elif typ == b"IEND":
            if laenge != 0:
                raise Kaputt("IEND ist nicht leer")
            at += 12 + laenge
            break
        else:
            if idat:
                idat_fertig = True
        if typ != b"IDAT" and idat:
            idat_fertig = True
        at += 12 + laenge
    if ihdr is None:
        raise Kaputt("kein IHDR")
    if not idat:
        raise Kaputt("kein IDAT")
    if not idat_zusammen:
        raise Kaputt("die IDAT-Chunks sind nicht zusammenhaengend")
    if at != len(roh):
        raise Kaputt("hinter IEND stehen noch %d Oktette -- die Datei "
                     "wurde beim Schreiben nicht gekuerzt (Acropalypse)"
                     % (len(roh) - at))
    return ihdr, b"".join(idat), len(roh)


def entpacke(strom, w, h, kanaele):
    if len(strom) < 6:
        raise Kaputt("der zlib-Strom ist zu kurz")
    kopf = (strom[0] << 8) | strom[1]
    if kopf % 31 != 0:
        raise Kaputt("der zlib-Kopf %04X ist nicht durch 31 teilbar" % kopf)
    if (strom[0] & 0x0F) != 8:
        raise Kaputt("der zlib-Kopf nennt ein anderes Verfahren als deflate")
    if strom[1] & 0x20:
        raise Kaputt("der zlib-Kopf verlangt ein Woerterbuch")
    d = zlib.decompressobj()
    roh = d.decompress(strom)
    roh += d.flush()
    if d.unused_data:
        raise Kaputt("hinter dem zlib-Strom stehen noch Oktette")
    # ADLER-32: die letzten vier Oktette des Stroms, gegen die Summe
    # ueber die GEFILTERTEN Zeilen. zlib prueft das selbst, aber nur,
    # wenn der Strom vollstaendig ankommt -- also wird es hier noch
    # einmal gerechnet, damit der Fehler einen Namen hat.
    (soll,) = struct.unpack(">I", strom[-4:])
    ist = zlib.adler32(roh) & 0xFFFFFFFF
    if soll != ist:
        raise Kaputt("ADLER-32: Datei sagt %08X, gerechnet %08X" % (soll, ist))
    bpp = kanaele
    zeile = w * bpp
    if len(roh) != (zeile + 1) * h:
        raise Kaputt("entpackt sind %d Oktette, erwartet %d"
                     % (len(roh), (zeile + 1) * h))
    aus = bytearray(zeile * h)
    vorher = bytearray(zeile)
    at = 0
    filter_gesehen = [0] * 5
    for y in range(h):
        art = roh[at]
        at += 1
        if art > 4:
            raise Kaputt("Zeile %d hat den Filter %d" % (y, art))
        filter_gesehen[art] += 1
        jetzt = bytearray(roh[at:at + zeile])
        at += zeile
        for i in range(zeile):
            a = jetzt[i - bpp] if i >= bpp else 0
            b = vorher[i]
            c = vorher[i - bpp] if i >= bpp else 0
            x = jetzt[i]
            if art == 1:
                x = (x + a) & 255
            elif art == 2:
                x = (x + b) & 255
            elif art == 3:
                x = (x + ((a + b) >> 1)) & 255
            elif art == 4:
                x = (x + paeth(a, b, c)) & 255
            jetzt[i] = x
        aus[y * zeile:(y + 1) * zeile] = jetzt
        vorher = jetzt
    return bytes(aus), filter_gesehen


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    pfad = sys.argv[1]
    ziel = None
    still = "--still" in sys.argv
    if "--raw" in sys.argv:
        ziel = sys.argv[sys.argv.index("--raw") + 1]
    try:
        ihdr, strom, groesse = lies(pfad)
        w, h, tiefe, art, komp, fil, inter = ihdr
        if tiefe != 8:
            raise Kaputt("Bittiefe %d -- dieser Leser will 8" % tiefe)
        if art not in (2, 6):
            raise Kaputt("Farbart %d -- dieser Leser will 2 oder 6" % art)
        if komp != 0 or fil != 0 or inter != 0:
            raise Kaputt("Kompression/Filter/Zeilensprung sind nicht 0/0/0")
        kanaele = 3 if art == 2 else 4
        roh, filter_gesehen = entpacke(strom, w, h, kanaele)
        if ziel:
            open(ziel, "wb").write(roh)
        if not still:
            print("PNGCHECK: %s -- %dx%d, Farbart %d, %d Oktette Datei, "
                  "%d entpackt" % (pfad, w, h, art, groesse, len(roh)))
            print("  filter  none=%d sub=%d up=%d avg=%d paeth=%d"
                  % tuple(filter_gesehen))
            print("  OK    Signatur, %d Chunks mit richtiger CRC, zlib mit "
                  "richtigem ADLER-32, nichts hinter IEND" % strom.count(b""))
        return 0
    except Kaputt as e:
        print("  FEHLER %s: %s" % (pfad, e))
        return 1
    except zlib.error as e:
        print("  FEHLER %s: der deflate-Strom ist kaputt (%s)" % (pfad, e))
        return 1


if __name__ == "__main__":
    sys.exit(main())
