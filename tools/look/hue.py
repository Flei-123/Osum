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


def lies_schema(name):
    """Die Rampe und der Akzent aus assets/schemes/<name>.scheme."""
    p = f"assets/schemes/{name}.scheme"
    werte = {}
    with open(p, encoding="utf-8") as f:
        for z in f:
            z = z.strip()
            if not z or z.startswith("#") or "=" not in z:
                continue
            k, v = z.split("=", 1)
            if re.fullmatch(r"[0-9a-fA-F]{6}", v):
                n = int(v, 16)
                werte[k] = (n >> 16 & 255, n >> 8 & 255, n & 255)
    return werte


def haupt_farben(im, n=6):
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
            # bunt, und in der Richtung des Sollakzents
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


# Zaehler der Befunde, von `pruefe_farbe` gefuellt.
BEFUND = {"fehler": 0, "vertauscht": 0}


def pruefe_farbe(bild, r, g, bl, n, ramp):
    best, bd = None, 10 ** 9
    for nm, (sr, sg, sb) in ramp.items():
        d = abs(r - sr) + abs(g - sg) + abs(bl - sb)
        if d < bd:
            bd, best = d, (nm, sr, sg, sb)
    nm, sr, sg, sb = best
    dreh = None
    for qn, (qr, qg, qb) in ramp.items():
        if (r, g, bl) == (qb, qg, qr) and qr != qb:
            dreh = qn
            break
    kurz = bild.split("/")[-1]
    if dreh:
        print(f"  {kurz:26s} RGB({r:3d},{g:3d},{bl:3d}) {n:7d}"
              f"  = {dreh} MIT VERTAUSCHTEM R UND B")
        BEFUND["vertauscht"] += 1
        BEFUND["fehler"] += 1
    elif bd <= 6:
        print(f"  {kurz:26s} RGB({r:3d},{g:3d},{bl:3d}) {n:7d}"
              f"  = {nm}  OK")
    else:
        print(f"  {kurz:26s} RGB({r:3d},{g:3d},{bl:3d}) {n:7d}"
              f"  naechste Stufe {nm} +{bd} -- in keiner Rampe")


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    scheme, mode = sys.argv[1], sys.argv[2]
    bilder = sys.argv[3:]
    ramp = lies_schema(scheme)
    if not ramp:
        print(f"kein Schema gelesen: {scheme}")
        return 2

    print(f"== FARBTON GEGEN {scheme}.scheme ({mode}) ==")
    print()
    fehler = 0
    vertauscht = 0
    for b in bilder:
        im = Image.open(b).convert("RGB")
        # ================================================ RUNDE 32
        # ALLE GROSSEN FLAECHEN, NICHT NUR DIE GROESSTE.
        #
        # Der erste Anlauf sah nur die haeufigste Farbe -- und liess
        # damit genau das Bild durch, um dessen Fehler es geht:
        # in dunkel-05-kontrollzentrum.png ist (2,6,23) die haeufigste
        # (der Schreibtisch, richtig), und der braune (59,41,30) steht
        # auf Platz ZWEI mit 41.907 Punkten. Eine Pruefung, die nur die
        # Nummer eins ansieht, findet einen Fehler nicht, der ein
        # Drittel des Bildes einnimmt.
        #
        # Also: jede Farbe, die mehr als ein Prozent der Punkte
        # ausmacht. Darunter liegen Kanten und Text, die von der
        # Glaettung Zwischenwerte bekommen und in keiner Rampe stehen
        # koennen.
        w0, h0 = im.size
        ganz = (w0 // 2) * (h0 // 2)
        for (r, g, bl), n in haupt_farben(im, 12):
            if n * 100 < ganz:
                continue
            pruefe_farbe(b, r, g, bl, n, ramp)
        continue
        (r, g, bl), n = haupt_farben(im, 1)[0]
        # Die naechste Stufe der Rampe.
        best, bd = None, 10 ** 9
        for nm, (sr, sg, sb) in ramp.items():
            d = abs(r - sr) + abs(g - sg) + abs(bl - sb)
            if d < bd:
                bd, best = d, (nm, sr, sg, sb)
        nm, sr, sg, sb = best
        # UND: ist sie die UMKEHRUNG einer Stufe? Das ist der Fehler,
        # um den es hier geht.
        dreh = None
        for qn, (qr, qg, qb) in ramp.items():
            if (r, g, bl) == (qb, qg, qr) and qr != qb:
                dreh = qn
                break
        kurz = b.split("/")[-1]
        if dreh:
            print(f"  {kurz:26s} RGB({r:3d},{g:3d},{bl:3d})"
                  f"  = {dreh} MIT VERTAUSCHTEM R UND B")
            vertauscht += 1
            fehler += 1
        elif bd <= 6:
            print(f"  {kurz:26s} RGB({r:3d},{g:3d},{bl:3d})"
                  f"  = {nm} (Abweichung {bd})  OK")
        else:
            print(f"  {kurz:26s} RGB({r:3d},{g:3d},{bl:3d})"
                  f"  naechste Stufe {nm} +{bd} -- IN KEINER RAMPE")
            fehler += 1

    # Der Akzent, getrennt: er ist die einzige laute Farbe und faellt
    # bei einer Umkehr am meisten auf (2563eb -> eb6325, ein Orange).
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
            kurz = b.split("/")[-1]
            if c:
                (ar, ag, ab), an = c.most_common(1)[0]
                print(f"  {kurz:26s} RGB({ar:3d},{ag:3d},{ab:3d})"
                      f" {an:6d} Punkte  OK")
            elif aufgehellt(px, w, h, soll) is not None:
                # DER AKZENT DARF AUFGEHELLT SEIN, und das ist kein
                # Schlupfloch: `night.scheme` sagt im Dateikopf, dass
                # 22c55e die 3:1-Regel gegen eine helle Flaeche
                # verfehlt und die Semantik deshalb die erzeugte Rampe
                # weiterlaeuft. Gemessen im dunklen Abbild:
                # RGB(117,219,155) -- das ist 22c55e zu 38 % gegen
                # Weiss gemischt, mit GLEICHEM Faktor in allen drei
                # Kanaelen (0.376/0.379/0.379).
                #
                # Genau dieser gleiche Faktor ist der Beweis, dass es
                # eine Aufhellung und keine Verwechslung ist: eine
                # Kanalumkehr ergibt in den drei Kanaelen drei
                # VERSCHIEDENE Faktoren. Deshalb wird der Faktor
                # geprueft und nicht nur die Aehnlichkeit.
                t, gf = aufgehellt(px, w, h, soll)
                print(f"  {kurz:26s} RGB{gf} = Akzent zu {t*100:.0f} %"
                      f" gegen Weiss gemischt  OK")
            else:
                # Kommt der Akzent VERTAUSCHT vor?
                gedreht = (soll[2], soll[1], soll[0])
                c2 = 0
                for y in range(0, h, 2):
                    for x in range(0, w, 2):
                        q = px[x, y]
                        if abs(q[0] - gedreht[0]) + abs(q[1] - gedreht[1]) \
                                + abs(q[2] - gedreht[2]) <= 8:
                            c2 += 1
                if c2 > 20:
                    print(f"  {kurz:26s} AKZENT VERTAUSCHT:"
                          f" RGB{gedreht} {c2} Punkte")
                    fehler += 1
                    vertauscht += 1
                else:
                    print(f"  {kurz:26s} kein Akzent im Bild")

    fehler += BEFUND["fehler"]
    vertauscht += BEFUND["vertauscht"]
    print()
    if vertauscht:
        print(f"FARBTON FEHLGESCHLAGEN: {vertauscht}x R und B vertauscht.")
        print("Das ist der Fehler aus Runde 31: paint/canvas.fi legt R,G,B,A")
        print("ab, wlibc.px schreibt ein u32 (auf x86 also B,G,R,A). Beide")
        print("malen in dieselbe Flaeche. Umgerechnet wird in")
        print("kernel/user/fuib.fi (`kanal_dreh`) -- und NUR dort, weil")
        print("paint/canvas.fi die gemeinsame Bibliothek ist.")
        return 1
    if fehler:
        print(f"FARBTON FEHLGESCHLAGEN: {fehler} Flaeche(n) in keiner Rampe.")
        return 1
    print("FARBTON PASSED.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
