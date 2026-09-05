#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/werkzeug/graphcheck.py -- STEHT DIE KURVE DA, WO SIE GEMELDET WURDE?

    graphcheck.py <bild.ppm> <serial.txt> <fensterx,fenstery>

Der Aufgabenverwalter malt seinen Verlaufsgraphen SELBST -- kein Widget
der Bibliothek, also auch keine `wlib: text`-Zeile, an der
`shotcheck.py` ihn messen koennte. Er meldet statt dessen:

    taskmgr: graph x= y= w= h= n= hist= p0x= p0y= pnx= pny=
    taskmgr: gcpu <n Werte in Promille>
    taskmgr: gmem <n Werte>

Daraus prueft dieses Werkzeug DREI Dinge im Bild, und keines davon
glaubt dem Programm auf sein Wort:

  1. DIE FLAECHE IST DA. Im gemeldeten Rechteck stehen Bildpunkte, und
     es sind nicht alle gleich -- eine einfarbige Flaeche waere ein
     Graph, der nichts zeichnet.
  2. DIE PUNKTE LIEGEN RICHTIG. Fuer jeden gemeldeten Messwert wird die
     Stelle ausgerechnet, an der er liegen muesste, und dort nach einem
     Bildpunkt gesucht, der sich vom Grund unterscheidet. Die Formel
     dafuer steht auch im Programm; damit sie nicht auseinanderlaufen
     koennen, meldet das Programm den ERSTEN und den LETZTEN Punkt
     zusaetzlich als fertige Bildpunktstelle -- stimmen die beiden
     Enden, stimmt die lineare Abbildung dazwischen.
  3. ZWEI KURVEN, ZWEI FARBEN. Im Rechteck kommen mindestens zwei
     Farben vor, die nicht der Grund und nicht das Gitter sind.

Der Rueckgabewert ist 0, wenn alle drei stimmen.
"""
import re
import sys

GR = re.compile(r"taskmgr: graph x=(\d+) y=(\d+) w=(\d+) h=(\d+) n=(\d+) "
                r"hist=(\d+) p0x=(\d+) p0y=(\d+) pnx=(\d+) pny=(\d+)")
CPU = re.compile(r"taskmgr: gcpu ([0-9 ]+)$")


def read_ppm(path):
    d = open(path, "rb").read()
    if not d.startswith(b"P6"):
        raise SystemExit("kein P6-PPM: %s" % path)
    f = []
    at = 2
    while len(f) < 3:
        while at < len(d) and d[at:at + 1].isspace():
            at += 1
        if d[at:at + 1] == b"#":
            while d[at:at + 1] not in (b"\n", b""):
                at += 1
            continue
        a = at
        while at < len(d) and not d[at:at + 1].isspace():
            at += 1
        f.append(int(d[a:at]))
    at += 1
    w, h, _ = f
    return w, h, d[at:]


class Bild:
    def __init__(self, path):
        self.w, self.h, self.px = read_ppm(path)

    def at(self, x, y):
        if x < 0 or y < 0 or x >= self.w or y >= self.h:
            return None
        i = (y * self.w + x) * 3
        return (self.px[i], self.px[i + 1], self.px[i + 2])


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    bild = Bild(argv[1])
    txt = open(argv[2], "rb").read().decode("latin1").splitlines()
    wx, wy = (int(v) for v in argv[3].split(","))

    g = None
    werte = None
    for z in txt:
        m = GR.search(z)
        if m:
            g = m
        m = CPU.search(z)
        if m:
            werte = [int(v) for v in m.group(1).split()]
    if g is None:
        print("keine graph-Zeile im Mitschnitt")
        return 1
    gx, gy, gw, gh, n, hist, p0x, p0y, pnx, pny = (int(v) for v in g.groups())
    # Fensterkoordinaten -> Schirmkoordinaten. Der Ursprung der
    # Arbeitsflaeche steht in der Spur der Bibliothek.
    cx, cy = wx + 2, wy + 22
    for z in txt:
        m = re.search(r"wlib: win id=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+) "
                      r"cx=(\d+) cy=(\d+)", z)
        if m and int(m.group(3)) > 400:
            cx, cy = int(m.group(5)), int(m.group(6))

    # ---- 1. die Flaeche
    farben = set()
    for y in range(gy + 2, gy + gh - 2, 3):
        for x in range(gx + 2, gx + gw - 2, 7):
            c = bild.at(cx + x, cy + y)
            if c:
                farben.add(c)
    print("Flaeche %dx%d an (%d,%d): %d verschiedene Farben"
          % (gw, gh, cx + gx, cy + gy, len(farben)))
    if len(farben) < 3:
        print("FEHLER: die Flaeche ist (fast) einfarbig -- da ist keine Kurve")
        return 1

    # ---- der Grund: die haeufigste Farbe der Flaeche
    zaehler = {}
    for y in range(gy + 2, gy + gh - 2):
        for x in range(gx + 2, gx + gw - 2, 3):
            c = bild.at(cx + x, cy + y)
            if c:
                zaehler[c] = zaehler.get(c, 0) + 1
    grund = max(zaehler, key=zaehler.get)
    print("Grundfarbe %s (%d von %d Punkten)"
          % (grund, zaehler[grund], sum(zaehler.values())))

    # ---- 2. die Punkte
    if not werte:
        print("keine gcpu-Werte (lief das Programm ohne `melde`?)")
        return 1
    treffer = 0
    daneben = 0
    for i, v in enumerate(werte[:n]):
        px_ = gx + 1 + i * (gw - 2) // hist
        innen = gh - 3
        py_ = gy + 1 + innen - min(v, 1000) * innen // 1000
        # In einem Fenster von drei Bildpunkten um die gemeldete Stelle
        # muss etwas stehen, das nicht der Grund ist.
        gut = False
        for dy in (-1, 0, 1, 2):
            for dx in (0, 1):
                c = bild.at(cx + px_ + dx, cy + py_ + dy)
                if c and c != grund:
                    gut = True
        if gut:
            treffer += 1
        else:
            daneben += 1
    print("Messpunkte %d: im Bild gefunden %d, daneben %d"
          % (n, treffer, daneben))
    # Die Enden, die das Programm selbst als Bildpunktstelle gemeldet hat
    e0 = gx + 1 + 0 * (gw - 2) // hist
    en = gx + 1 + (n - 1) * (gw - 2) // hist
    print("Enden: gemeldet p0x=%d pnx=%d, nachgerechnet %d und %d"
          % (p0x, pnx, e0, en))
    if p0x != e0 or pnx != en:
        print("FEHLER: die Abbildung des Laeufers und die des Programms "
              "laufen auseinander")
        return 1
    if treffer * 4 < n * 3:
        print("FEHLER: weniger als drei Viertel der Messpunkte stehen im Bild")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
