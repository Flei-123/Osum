#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    icon.py <zeichnung.txt> <output>
    icon.py --check <output> <zeichnung.txt>   liest back
"""

import struct
import sys

ROLLEN = {
    "ink": 1,
    "dim": 2,
    "accent": 3,
    "warn": 4,
    "panel": 5,
}


def read_2(path_2):
    palette = {}
    rows = []
    for roh in open(path_2, encoding="ascii").read().splitlines():
        if roh.startswith("#"):
            part = roh[1:].strip()
            if "=" in part:
                chars, _, value = part.partition("=")
                chars = chars.strip()
                value = value.strip()
                if len(chars) != 1:
                    raise SystemExit(
                        "symbol: '%s' ist kein einzelnes Zeichen" % chars)
                if not value:
                    palette[chars] = None
                elif value.startswith("@"):
                    name = value[1:]
                    if name not in ROLLEN:
                        raise SystemExit(
                            "symbol: '@%s' ist keine Rolle (%s)"
                            % (name, ", ".join(sorted(ROLLEN))))
                    palette[chars] = ("rolle", ROLLEN[name])
                else:
                    if len(value) != 6:
                        raise SystemExit(
                            "symbol: '%s' sind nicht sechs Hexziffern" % value)
                    palette[chars] = int(value, 16)
            continue
        if roh.strip() == "":
            continue
        rows.append(roh)
    if not rows:
        raise SystemExit("symbol: %s hat keine Zeile Bild" % path_2)
    width_2 = len(rows[0])
    for i, z in enumerate(rows):
        if len(z) != width_2:
            raise SystemExit("symbol: Zeile %d ist %d Zeichen breit, die "
                             "erste %d" % (i + 1, len(z), width_2))
    for z in rows:
        for c in z:
            if c not in palette:
                raise SystemExit("symbol: '%s' steht in keiner Palette" % c)
    return palette, rows


def build(path_2):
    palette, rows = read_2(path_2)
    h = len(rows)
    w = len(rows[0])
    aus = bytearray(b"OSYM")
    aus += struct.pack("<II", w, h)
    for z in rows:
        for c in z:
            rgb = palette[c]
            if rgb is None:
                aus += bytes(4)
            elif isinstance(rgb, tuple):
                aus += bytes((0, 0, 0, rgb[1]))
            else:
                aus += bytes(((rgb & 255), (rgb >> 8) & 255,
                              (rgb >> 16) & 255, 255))
    return bytes(aus)


def back(path_2):
    d = open(path_2, "rb").read()
    if len(d) < 12 or d[:4] != b"OSYM":
        raise SystemExit("symbol: %s faengt nicht mit OSYM an" % path_2)
    w, h = struct.unpack_from("<II", d, 4)
    if len(d) < 12 + w * h * 4:
        raise SystemExit("symbol: %s ist zu kurz fuer %dx%d" % (path_2, w, h))
    aus = []
    for y in range(h):
        reihe = []
        for x in range(w):
            b, g, r, a = d[12 + (y * w + x) * 4:12 + (y * w + x) * 4 + 4]
            if a == 0:
                reihe.append(None)
            elif a != 255 and w >= 32 and h >= 32:
                reihe.append(None)
            elif a != 255:
                reihe.append(("rolle", a))
            else:
                reihe.append((r << 16) | (g << 8) | b)
        aus.append(reihe)
    return w, h, aus


def main(argv):
    if len(argv) >= 4 and argv[1] == "--check" and argv[3].endswith(".osym"):
        import os
        import symjoin
        want = symjoin.joined(os.path.dirname(argv[3]) or ".")
        if open(argv[2], "rb").read() == want:
            print("symbol.osym, %d Oktette, gleich" % len(want))
            return 0
        print("symbol: the image does not carry the octets of %s (with the row images)" % argv[3])
        return 1
    if len(argv) >= 4 and argv[1] == "--check":
        w, h, image = back(argv[2])
        palette, rows = read_2(argv[3])
        if h != len(rows) or w != len(rows[0]):
            print("symbol: %dx%d in the image, %dx%d in the drawing"
                  % (w, h, len(rows[0]), len(rows)))
            return 1
        wrong = 0
        for y in range(h):
            for x in range(w):
                if image[y][x] != palette[rows[y][x]]:
                    wrong += 1
        if wrong:
            print("symbol: %d of %d pixels different" % (wrong, w * h))
            return 1
        print("symbol: %dx%d, %d pixels, all equal" % (w, h, w * h))
        return 0
    if len(argv) != 3:
        print(__doc__)
        return 2
    d = build(argv[1])
    with open(argv[2], "wb") as f:
        f.write(d)
    print("symbol: %s  %d Oktette" % (argv[2], len(d)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
