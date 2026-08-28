#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/certus/pixel.py -- EIN BILD WIRD GEZAEHLT, NICHT ANGESCHAUT.

Die Falle, gegen die dieses Skript geschrieben ist, ist die aus Runde
K7B: ein Programm meldet, es habe gemalt, und der Bildschirm ist leer.
Ein Mensch, der ein Bild anschaut, faellt darauf nicht herein -- eine
Abnahme, die nur Textzeilen liest, schon.

Gezaehlt wird dreierlei, und jedes davon trennt einen anderen Fehlerfall
ab:

  TINTENPUNKTE    Punkte, die nicht die haeufigste Farbe haben. Null
                  heisst: die Flaeche ist einfarbig, es steht nichts da.
  DUNKLE PUNKTE   Punkte unter 96 in allen drei Kanaelen. Ein Browser,
                  der die Kaesten einer Seite malt und die Buchstaben
                  nicht, hat Tinte und KEINE dunklen Punkte -- genau der
                  Fehler, den Runde B5 mit `xwd` gefunden hat.
  TEXTBAENDER     Waagrechte Baender, in denen mindestens drei dunkle
                  Punkte stehen. Ein Kasten ist EIN Band; ein Absatz aus
                  vier Zeilen sind vier. Damit laesst sich "es steht ein
                  schwarzer Balken da" von "es steht Text da" trennen.

    pixel.py <bild.ppm> [--json <datei>] [--png <datei>] [--fenster]
             [--oben <n>]

`--fenster` laesst die oberen 30 Zeilen (die Bedienleiste) und die
unteren 32 (die Taskleiste) aus der Zaehlung heraus, damit ein Bild vom
ganzen Bildschirm dieselbe Zahl ergibt wie eine Leinwand ohne beides.
"""
import json
import struct
import sys
import zlib
from collections import Counter


def read_ppm(path):
    b = open(path, "rb").read()
    if not b.startswith(b"P6"):
        return None
    parts = []
    i = 2
    while len(parts) < 3:
        while i < len(b) and b[i:i + 1].isspace():
            i += 1
        if i < len(b) and b[i:i + 1] == b"#":
            while i < len(b) and b[i:i + 1] != b"\n":
                i += 1
            continue
        j = i
        while j < len(b) and not b[j:j + 1].isspace():
            j += 1
        parts.append(int(b[i:j]))
        i = j
    i += 1
    w, h, _ = parts
    return w, h, b[i:i + w * h * 3]


def write_png(path, w, h, px):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += px[y * w * 3:(y + 1) * w * 3]

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    out = b"\x89PNG\r\n\x1a\n"
    out += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    out += chunk(b"IEND", b"")
    open(path, "wb").write(out)


def zaehlen(w, h, px, y0=0, y1=None):
    if y1 is None:
        y1 = h
    cnt = Counter()
    for y in range(y0, y1):
        base = y * w * 3
        for x in range(w):
            o = base + x * 3
            cnt[px[o:o + 3]] += 1
    if not cnt:
        return {}
    bg = cnt.most_common(1)[0][0]
    ink = sum(v for k, v in cnt.items() if k != bg)
    dark = sum(v for k, v in cnt.items()
               if k[0] < 96 and k[1] < 96 and k[2] < 96)
    baender = 0
    drin = False
    for y in range(y0, y1):
        base = y * w * 3
        d = 0
        for x in range(w):
            o = base + x * 3
            if px[o] < 96 and px[o + 1] < 96 and px[o + 2] < 96:
                d += 1
        if d >= 3 and not drin:
            baender += 1
            drin = True
        elif d < 3:
            drin = False
    flaeche = w * (y1 - y0)
    return {
        "breite": w,
        "hoehe": y1 - y0,
        "hintergrund": "#%02x%02x%02x" % (bg[0], bg[1], bg[2]),
        "tintenpunkte": ink,
        "tintenanteil": round(ink / float(flaeche), 5) if flaeche else 0,
        "dunkle_punkte": dark,
        "farben": len(cnt),
        "textbaender": baender,
    }


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    bild = sys.argv[1]
    args = sys.argv[2:]
    p = read_ppm(bild)
    if p is None:
        print("kein P6-PPM: %s" % bild)
        return 1
    w, h, px = p
    if "--png" in args:
        write_png(args[args.index("--png") + 1], w, h, px)
    y0, y1 = 0, h
    if "--fenster" in args:
        y0 = min(30, h)
        y1 = max(y0, h - 32)
    if "--oben" in args:
        y0 = int(args[args.index("--oben") + 1])
    r = zaehlen(w, h, px, y0, y1)
    if "--json" in args:
        json.dump(r, open(args[args.index("--json") + 1], "w"), indent=2)
    print("%dx%d  Hintergrund %s  Tinte %d (%.2f %%)  dunkel %d  "
          "Farben %d  Baender %d"
          % (r.get("breite", 0), r.get("hoehe", 0),
             r.get("hintergrund", "-"), r.get("tintenpunkte", 0),
             100.0 * r.get("tintenanteil", 0), r.get("dunkle_punkte", 0),
             r.get("farben", 0), r.get("textbaender", 0)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
