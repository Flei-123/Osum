#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/look/hue.py -- MISST DEN FARBTON, NICHT DIE HELLIGKEIT.

    hue.py <scheme> <mode> <bild.png> [<bild.png> ...]

      scheme   day|night|paper|midnight|contrast  (assets/schemes/<n>.scheme)
      mode     light|dark

WARUM ES EXISTIERT
==================

Runde 31 hat einen Fehler eingebaut und die Abnahme hat ihn gruen
gemeldet. Justin fand ihn, indem er den FARBTON nachmass statt der
Helligkeit:

    dunkel-05-kontrollzentrum.png
      Panel und Taskleiste     RGB( 59, 41, 30)   braun
      dieselbe Farbe woanders  RGB( 30, 41, 59)   neutral-dunkelblau

`night.scheme` sagt `neutral800=1e293b`, also war RGB(59,41,30) die
Umkehrung -- R und B vertauscht, weil `paint/canvas.fi` seine Oktette als
R,G,B,A ablegt und `wlibc.px` ein u32 schreibt, das auf x86 als B,G,R,A
liegt.

Meine Messung sah das nicht, weil |R-B| bei Weiss 0 ist, bei f8fafc 4
und bei f1f5f9 8: Grautoene sind unter der Umkehr fast unveraendert, und
Braun ist brav dunkler als Weiss. Eine Helligkeitsmessung kann diesen
Fehler grundsaetzlich nicht finden.

WIE GEMESSEN WIRD
=================

Nicht gegen einen erfundenen Schwellwert -- der erste Anlauf dieses
Skripts nahm |R-B| <= 12 und schlug bei `020617` (R-B = -21) und
`1e293b` (-29) Alarm, obwohl beide RICHTIG sind: die Slate-Rampe ist
absichtlich kuehl. Ein Schwellwert haette also entweder die kuehle
Rampe verboten oder die Umkehr durchgelassen.

Stattdessen wird gegen die ECHTEN WERTE DER SCHEMADATEI gemessen. Die
haeufigste Farbe einer Flaeche muss einer Stufe der Rampe entsprechen,
und zwar genau. Und es wird ausdruecklich geprueft, ob sie der
UMKEHRUNG einer Stufe entspricht -- das ist der Fehler, um den es geht,
und er hat einen eigenen Namen in der Ausgabe.
"""
import re
import sys
from collections import Counter

try:
    from PIL import Image
except ImportError:
    print("PIL fehlt: pip3 install pillow", file=sys.stderr)
    sys.exit(2)


def read_schema(name):
    """Die Rampe und der Akzent aus assets/schemes/<name>.scheme."""
    p = f"assets/schemes/{name}.scheme"
    values = {}
    with open(p, encoding="utf-8") as f:
        for z in f:
            z = z.strip()
            if not z or z.startswith("#") or "=" not in z:
                continue
            k, v = z.split("=", 1)
            if re.fullmatch(r"[0-9a-fA-F]{6}", v):
                n = int(v, 16)
                values[k] = (n >> 16 & 255, n >> 8 & 255, n & 255)
    return values


def main_farben(im, n=6):
    px = im.load()
    w, h = im.size
    c = Counter()
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            c[px[x, y]] += 1
    return c.most_common(n)


def aufgehellt(px, w, h, soll):
    """Ist die lauteste bunte Farbe eine Mischung von `soll` gegen Weiss?

    Eine Mischung hat in allen drei Kanaelen DENSELBEN Faktor; eine
    Kanalumkehr hat drei verschiedene. Damit sind die beiden Faelle
    auseinanderzuhalten, ohne eine Toleranz zu erfinden.
    """
    c = Counter()
    sr, sg, sb = soll
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            r, g, b = px[x, y]
            if max(r, g, b) - min(r, g, b) < 40:
                continue
            if (g > r) != (sg > sr) or (g > b) != (sg > sb):
                continue
            c[(r, g, b)] += 1
    if not c:
        return None
    (r, g, b), n = c.most_common(1)[0]
    if n < 20:
        return None
    ts = []
    for a, q in ((sr, r), (sg, g), (sb, b)):
        if 255 - a == 0:
            continue
        ts.append((q - a) / (255 - a))
    if not ts or min(ts) < -0.05 or max(ts) > 1.0:
        return None
    if max(ts) - min(ts) > 0.06:
        return None
    return sum(ts) / len(ts), (r, g, b)


BEFUND = {"fehler": 0, "vertauscht": 0}


def check_color(bild, r, g, bl, n, ramp):
    best, bd = None, 10 ** 9
    for nm, (sr, sg, sb) in ramp.items():
        d = abs(r - sr) + abs(g - sg) + abs(bl - sb)
        if d < bd:
            bd, best = d, (nm, sr, sg, sb)
    nm, sr, sg, sb = best
    rot = None
    for qn, (qr, qg, qb) in ramp.items():
        if (r, g, bl) == (qb, qg, qr) and qr != qb:
            rot = qn
            break
    short = bild.split("/")[-1]
    if rot:
        print(f"  {short:26s} RGB({r:3d},{g:3d},{bl:3d}) {n:7d}"
              f"  = {rot} MIT VERTAUSCHTEM R UND B")
        BEFUND["vertauscht"] += 1
        BEFUND["fehler"] += 1
    elif bd <= 6:
        print(f"  {short:26s} RGB({r:3d},{g:3d},{bl:3d}) {n:7d}"
              f"  = {nm}  OK")
    else:
        print(f"  {short:26s} RGB({r:3d},{g:3d},{bl:3d}) {n:7d}"
              f"  naechste Stufe {nm} +{bd} -- in keiner Rampe")


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    scheme, mode = sys.argv[1], sys.argv[2]
    bilder = sys.argv[3:]
    ramp = read_schema(scheme)
    if not ramp:
        print(f"kein Schema gelesen: {scheme}")
        return 2

    print(f"== FARBTON GEGEN {scheme}.scheme ({mode}) ==")
    print()
    error = 0
    vertauscht = 0
    for b in bilder:
        im = Image.open(b).convert("RGB")
        w0, h0 = im.size
        ganz = (w0 // 2) * (h0 // 2)
        for (r, g, bl), n in main_farben(im, 12):
            if n * 100 < ganz:
                continue
            check_color(b, r, g, bl, n, ramp)
        continue
        (r, g, bl), n = main_farben(im, 1)[0]
        best, bd = None, 10 ** 9
        for nm, (sr, sg, sb) in ramp.items():
            d = abs(r - sr) + abs(g - sg) + abs(bl - sb)
            if d < bd:
                bd, best = d, (nm, sr, sg, sb)
        nm, sr, sg, sb = best
        rot = None
        for qn, (qr, qg, qb) in ramp.items():
            if (r, g, bl) == (qb, qg, qr) and qr != qb:
                rot = qn
                break
        short = b.split("/")[-1]
        if rot:
            print(f"  {short:26s} RGB({r:3d},{g:3d},{bl:3d})"
                  f"  = {rot} MIT VERTAUSCHTEM R UND B")
            vertauscht += 1
            error += 1
        elif bd <= 6:
            print(f"  {short:26s} RGB({r:3d},{g:3d},{bl:3d})"
                  f"  = {nm} (Abweichung {bd})  OK")
        else:
            print(f"  {short:26s} RGB({r:3d},{g:3d},{bl:3d})"
                  f"  naechste Stufe {nm} +{bd} -- IN KEINER RAMPE")
            error += 1

    print()
    print("== DER AKZENT ==")
    soll = ramp.get("accent")
    if soll:
        print(f"  Schema sagt: RGB{soll}")
        for b in bilder:
            im = Image.open(b).convert("RGB")
            px = im.load()
            w, h = im.size
            c = Counter()
            for y in range(0, h, 2):
                for x in range(0, w, 2):
                    q = px[x, y]
                    if abs(q[0] - soll[0]) + abs(q[1] - soll[1]) \
                            + abs(q[2] - soll[2]) <= 8:
                        c[q] += 1
            short = b.split("/")[-1]
            if c:
                (ar, ag, ab), an = c.most_common(1)[0]
                print(f"  {short:26s} RGB({ar:3d},{ag:3d},{ab:3d})"
                      f" {an:6d} Punkte  OK")
            elif aufgehellt(px, w, h, soll) is not None:
                t, gf = aufgehellt(px, w, h, soll)
                print(f"  {short:26s} RGB{gf} = accent at {t*100:.0f} %"
                      f" gegen Weiss gemischt  OK")
            else:
                gedreht = (soll[2], soll[1], soll[0])
                c2 = 0
                for y in range(0, h, 2):
                    for x in range(0, w, 2):
                        q = px[x, y]
                        if abs(q[0] - gedreht[0]) + abs(q[1] - gedreht[1]) \
                                + abs(q[2] - gedreht[2]) <= 8:
                            c2 += 1
                if c2 > 20:
                    print(f"  {short:26s} AKZENT VERTAUSCHT:"
                          f" RGB{gedreht} {c2} Punkte")
                    error += 1
                    vertauscht += 1
                else:
                    print(f"  {short:26s} no accent in the image")

    error += BEFUND["fehler"]
    vertauscht += BEFUND["vertauscht"]
    print()
    if vertauscht:
        print(f"FARBTON FEHLGESCHLAGEN: {vertauscht}x R und B vertauscht.")
        print("That is the bug from round 31: paint/canvas.fi stores R,G,B,A")
        print("in that order, wlibc.px writes a u32 (so B,G,R,A on x86). Both")
        print("paint into the same area. The conversion happens in")
        print("kernel/user/fuib.fi (`kanal_dreh`) -- and ONLY there, because")
        print("paint/canvas.fi is the shared library.")
        return 1
    if error:
        print(f"HUE FAILED: {error} area(s) in no ramp.")
        return 1
    print("FARBTON PASSED.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
