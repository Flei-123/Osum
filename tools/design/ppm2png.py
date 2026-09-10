#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/design/ppm2png.py -- PPM nach PNG, ohne fremde Bibliothek.

Die Aufnahmen entstehen als PPM (das schreibt QEMUs `screendump`), und
PPM ist unkomprimiert: ein Bild in 2560x1440 sind 11 MB. Als Beleg
abgelegt werden sie deshalb als PNG -- verlustfrei, also derselbe
Bildinhalt, nur ein Zehntel so gross.

    python3 tools/design/ppm2png.py <ein.ppm> <aus.png>

Kein Pillow: dieses Projekt haelt seine Werkzeuge frei von Abhaengig-
keiten, die es nur zum Verpacken braucht. zlib ist in der Standard-
bibliothek, und mehr als ein IHDR, ein IDAT und ein IEND braucht ein
Vollfarb-PNG nicht.
"""
import sys, zlib, struct


def read_ppm(p):
    d = open(p, "rb").read()
    parts = []
    i = 0
    while len(parts) < 4:
        while i < len(d) and d[i:i + 1].isspace():
            i += 1
        if d[i:i + 1] == b"#":
            while d[i:i + 1] not in (b"\n", b""):
                i += 1
            continue
        s = i
        while i < len(d) and not d[i:i + 1].isspace():
            i += 1
        parts.append(d[s:i])
    i += 1
    w, h = int(parts[1]), int(parts[2])
    return w, h, d[i:i + w * h * 3]


def chunk(typ, data):
    c = typ + data
    return (struct.pack(">I", len(data)) + c
            + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF))


def main(src, dst):
    w, h, px = read_ppm(src)
    # Filtertyp 0 je Zeile -- PNG verlangt das Byte, und "keine
    # Vorhersage" ist bei einem Bildschirmfoto mit grossen einfarbigen
    # Flaechen kaum schlechter als die klugen Filter.
    raw = b"".join(b"\x00" + px[y * w * 3:(y + 1) * w * 3] for y in range(h))
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 6))
           + chunk(b"IEND", b""))
    open(dst, "wb").write(png)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
