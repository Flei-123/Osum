#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/gfx/ppm2png.py -- ein PPM in ein PNG, ohne Fremdbibliothek.

QEMU schreibt Bildschirmfotos als PPM (`screendump`), und PPM ist fuer
das Nachrechnen genau richtig: drei Oktette je Bildpunkt, kein Verfahren
dazwischen, jedes Werkzeug dieses Repos liest es direkt. Zum ANSEHEN ist
es unbrauchbar -- ein Bild von 800x600 sind 1,4 Megaoktett, und kein
Betrachter ausserhalb dieses Repos oeffnet es gern.

Deshalb diese Datei. Sie haengt an NICHTS ausser `zlib` aus der
Standardbibliothek: ein PNG ist ein Kopf, ein deflate-Strom aus Zeilen
mit je einem Filteroktett davor, und drei CRC32. Pillow waere ein
Fremdpaket, und ein Testlaeufer, der ohne Netz nicht durchlaeuft, ist
kein Testlaeufer.

GEFILTERT WIRD MIT 1 ("Sub", der linke Nachbar). Bei einer Oberflaeche
mit grossen einfarbigen Flaechen ist das der Unterschied zwischen
900 Kilooktett und 30 -- und Filter 0 waere zwar kuerzer zu schreiben,
aber die Fotos landen im Repo.

    ppm2png.py <quelle.ppm> <ziel.png>
"""

import struct
import sys
import zlib


def ppm_read(path_2):
    """P6 lesen. Der Kopf darf Kommentare enthalten, und die Felder
    duerfen durch beliebigen Zwischenraum getrennt sein -- so steht es
    in der Beschreibung des Formats, und QEMU haelt sich daran."""
    with open(path_2, "rb") as f:
        roh = f.read()
    if not roh.startswith(b"P6"):
        raise SystemExit("ppm2png: kein P6-PPM: %s" % path_2)
    at = 2
    felder = []
    while len(felder) < 3:
        while at < len(roh) and roh[at:at + 1].isspace():
            at += 1
        if roh[at:at + 1] == b"#":
            while at < len(roh) and roh[at:at + 1] != b"\n":
                at += 1
            continue
        begin = at
        while at < len(roh) and not roh[at:at + 1].isspace():
            at += 1
        felder.append(int(roh[begin:at]))
    at += 1
    b, h, up = felder
    if up != 255:
        raise SystemExit("ppm2png: nur 8 Bit je Kanal, nicht %d" % up)
    data_2 = roh[at:at + b * h * 3]
    if len(data_2) < b * h * 3:
        raise SystemExit("ppm2png: %d Oktette zu wenig"
                         % (b * h * 3 - len(data_2)))
    return b, h, data_2


def chunk(art, nutz):
    return (struct.pack(">I", len(nutz)) + art + nutz
            + struct.pack(">I", zlib.crc32(art + nutz) & 0xFFFFFFFF))


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    b, h, data_2 = ppm_read(argv[1])

    zeilen = bytearray()
    schritt = b * 3
    for y in range(h):
        z = data_2[y * schritt:(y + 1) * schritt]
        zeilen.append(1)
        zeilen += z[:3]
        vorher = memoryview(z)[:-3]
        now = memoryview(z)[3:]
        zeilen += bytes((a - c) & 255 for a, c in zip(now, vorher))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", b, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(zeilen), 9))
    png += chunk(b"IEND", b"")
    with open(argv[2], "wb") as f:
        f.write(png)
    print("ppm2png: %dx%d -> %s (%d Oktette)"
          % (b, h, argv[2], len(png)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
