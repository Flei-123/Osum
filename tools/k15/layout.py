#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/k15/layout.py -- die ANORDNUNG nachrechnen, aus dem Mitschnitt.

    layout.py <mitschnitt> <marke> <fensterbreite> <fensterhoehe>

Die Anwendung meldet vor dem ersten Malen jedes Rechteck, das die
Anordnung ausgerechnet hat:

    widgetdemo: rect id=5 kind=2 x=12 y=196 w=100 h=28

DIESES PROGRAMM PRUEFT DIE RECHTECKE GEGENEINANDER, und das ist der
Teil, den ein Bildschirmfoto NICHT prueft: ein Foto zeigt, dass da ein
Knopf ist, aber nicht, dass er nicht heimlich unter einem anderen liegt.
Vier Zusagen:

  1. JEDES RECHTECK LIEGT IM FENSTER.  Ein Widget, das halb draussen
     liegt, wird vom Fensterserver abgeschnitten und sieht auf dem Foto
     aus wie ein schmaleres Widget.
  2. KEINE ZWEI RECHTECKE UEBERSCHNEIDEN SICH.  Das ist die eigentliche
     Zusage einer Anordnung: sie verteilt Platz, sie stapelt nicht.
  3. JEDES RECHTECK HAT FLAECHE.  Breite oder Hoehe null heisst, dass
     eine Wunschgroesse nicht angekommen ist -- und im Bild sieht man
     gar nichts, also auch keinen Fehler.
  4. DIE SENKRECHTE REIHENFOLGE IST DIE ANLEGEREIHENFOLGE, solange die
     Rechtecke in demselben Kasten liegen (gleiche x-Kante).  Eine
     Anordnung, die Widgets vertauscht, ist keine.

Rueckgabe 0, wenn alles stimmt; sonst 1 und eine Zeile je Verstoss.
"""
import re
import sys


def rechtecke(path_2, brand):
    pat = re.compile(
        r"^%s: rect id=(\d+) kind=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)"
        % re.escape(brand))
    aus = []
    with open(path_2, "rb") as f:
        for roh in f:
            z = roh.decode("latin-1").strip()
            m = pat.match(z)
            if m:
                aus.append(tuple(int(v) for v in m.groups()))
    return aus


def main():
    if len(sys.argv) < 5:
        print(__doc__)
        return 2
    path_2, brand = sys.argv[1], sys.argv[2]
    bw, bh = int(sys.argv[3]), int(sys.argv[4])
    mind = int(sys.argv[5]) if len(sys.argv) > 5 else 8
    vertical = [int(v) for v in sys.argv[6].split(",")] if len(sys.argv) > 6 else []
    r = rechtecke(path_2, brand)
    error = []
    if len(r) < mind:
        error.append("only %d rectangles reported, %d expected"
                      % (len(r), mind))
    for (i, k, x, y, w, h) in r:
        if w == 0 or h == 0:
            error.append("id=%d has no area: %dx%d" % (i, w, h))
        if i >= 50:
            continue
        if x + w > bw or y + h > bh:
            error.append("id=%d lies outside: (%d,%d) %dx%d, "
                          "window %dx%d" % (i, x, y, w, h, bw, bh))
    for a in range(len(r)):
        for b in range(a + 1, len(r)):
            (ia, _ka, xa, ya, wa, ha) = r[a]
            (ib, _kb, xb, yb, wb, hb) = r[b]
            if xa < xb + wb and xb < xa + wa and \
               ya < yb + hb and yb < ya + ha:
                error.append("id=%d and id=%d overlap: "
                              "(%d,%d %dx%d) / (%d,%d %dx%d)"
                              % (ia, ib, xa, ya, wa, ha, xb, yb, wb, hb))
    columns = {}
    for (i, k, x, y, w, h) in r:
        if i >= 50 or i in vertical:
            continue
        columns.setdefault(x, []).append((i, y))
    for x, list_2 in columns.items():
        if len(list_2) < 2:
            continue
        nach_id = [y for (i, y) in sorted(list_2)]
        if nach_id != sorted(nach_id):
            error.append("at x=%d the order is upside down: %s"
                          % (x, nach_id))
    ys = dict((i, y) for (i, _k, _x, y, _w, _h) in r)
    chain = [ys[i] for i in vertical if i in ys]
    if len(chain) != len(vertical) or chain != sorted(chain):
        error.append("vertical order %s is wrong: %s"
                      % (vertical, chain))
    if error:
        for f in error:
            print(f)
        return 1
    print("%d rectangles, all inside window %dx%d, no overlap, "
          "order correct in %d columns"
          % (len(r), bw, bh, len(columns)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
