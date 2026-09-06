#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/lupe.py -- EIN AUSSCHNITT, VERGROESSERT, VORHER NEBEN NACHHER.
#
#   lupe.py <ansicht> <x> <y> <b> <h> [zoom] [ziel.png]
#
# Der Vergleich in gegenueber.py zeigt zwei ganze Bildschirme
# nebeneinander.  Bei 1920x1080 auf einer Bildschirmbreite ist ein
# Radius von 12 Bildpunkten drei Bildpunkte gross -- man sieht ihn
# nicht, man glaubt ihn.  Dieses Werkzeug schneidet DIESELBE Stelle aus
# beiden Aufnahmen und vergroessert sie, damit die Ecke, der Schatten
# und die Kantenglaettung SICHTBAR werden und nicht behauptet bleiben.
import sys, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHOTS = os.path.join(ROOT, ".design2-shots")


def lies_ppm(p):
    with open(p, "rb") as f:
        d = f.read()
    # P6, Weiss/Hoehe, Maxwert -- der Kopf ist ASCII und durch
    # Leerraum getrennt, Kommentare mit '#'.
    felder = []
    i = 0
    while len(felder) < 4:
        while i < len(d) and d[i : i + 1].isspace():
            i += 1
        if d[i : i + 1] == b"#":
            while i < len(d) and d[i] != 0x0A:
                i += 1
            continue
        j = i
        while j < len(d) and not d[j : j + 1].isspace():
            j += 1
        felder.append(d[i:j])
        i = j
    i += 1
    w = int(felder[1]); h = int(felder[2])
    return w, h, d[i : i + w * h * 3]


def schreib_png(p, w, h, roh):
    import zlib, struct
    z = b"".join(b"\x00" + roh[y * w * 3 : (y + 1) * w * 3] for y in range(h))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(z, 9))
    png += chunk(b"IEND", b"")
    with open(p, "wb") as f:
        f.write(png)


def schnitt(w, h, roh, x0, y0, bw, bh, zoom):
    ow, oh = bw * zoom, bh * zoom
    aus = bytearray(ow * oh * 3)
    for y in range(oh):
        sy = y0 + y // zoom
        for x in range(ow):
            sx = x0 + x // zoom
            if 0 <= sx < w and 0 <= sy < h:
                s = (sy * w + sx) * 3
                d = (y * ow + x) * 3
                aus[d : d + 3] = roh[s : s + 3]
    return ow, oh, bytes(aus)


def main():
    if len(sys.argv) < 6:
        print(__doc__ or "lupe.py <ansicht> <x> <y> <b> <h> [zoom] [ziel]")
        return 2
    ansicht = sys.argv[1]
    x0, y0, bw, bh = (int(v) for v in sys.argv[2:6])
    zoom = int(sys.argv[6]) if len(sys.argv) > 6 else 6
    ziel = sys.argv[7] if len(sys.argv) > 7 else os.path.join(
        SHOTS, "lupe", "lupe-%s.png" % ansicht)
    os.makedirs(os.path.dirname(ziel), exist_ok=True)

    teile = []
    for lauf in ("vorher-run", "nachher-run"):
        p = os.path.join(SHOTS, lauf, "bilder", ansicht + ".ppm")
        if not os.path.exists(p):
            print("fehlt: %s" % p)
            return 1
        w, h, roh = lies_ppm(p)
        teile.append(schnitt(w, h, roh, x0, y0, bw, bh, zoom))

    lw, lh, _ = teile[0]
    spalt = 8
    gw = lw * 2 + spalt
    aus = bytearray(b"\x20" * (gw * lh * 3))
    for k, (tw, th, td) in enumerate(teile):
        ox = k * (lw + spalt)
        for y in range(th):
            d = (y * gw + ox) * 3
            s = y * tw * 3
            aus[d : d + tw * 3] = td[s : s + tw * 3]
    schreib_png(ziel, gw, lh, bytes(aus))
    print("%s  (links vorher, rechts nachher, %dx%d, zoom %d)"
          % (ziel, gw, lh, zoom))
    return 0


if __name__ == "__main__":
    sys.exit(main())
