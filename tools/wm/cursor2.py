#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import sys

G = 24.0

NAMEN = ["pfeil", "text", "hand", "breite", "hoehe",
         "diag1", "diag2", "kreuz", "warten", "verboten", "kopie", "ziel"]


def _rot(pts, grad, cx=12.0, cy=12.0):
    import math
    a = math.radians(grad)
    s, c = math.sin(a), math.cos(a)
    out = []
    for (x, y) in pts:
        dx, dy = x - cx, y - cy
        out.append((cx + dx * c - dy * s, cy + dx * s + dy * c))
    return out


PFEIL = [(2.0, 2.0), (2.0, 19.0), (6.2, 15.0), (8.9, 21.4),
         (11.6, 20.2), (8.9, 14.0), (13.6, 14.0)]

TEXT = [(8.5, 3.5), (15.5, 3.5), (15.5, 5.1), (12.9, 5.1),
        (12.9, 18.9), (15.5, 18.9), (15.5, 20.5), (8.5, 20.5),
        (8.5, 18.9), (11.1, 18.9), (11.1, 5.1), (8.5, 5.1)]

HAND_ROH = [(8.0, 2.5), (10.6, 2.5), (11.4, 3.4), (11.4, 11.4),
        (12.6, 10.6), (15.0, 10.6), (15.8, 11.4),
        (16.4, 10.9), (18.4, 10.9), (19.2, 11.7),
        (19.6, 11.4), (21.2, 11.4), (22.0, 12.3),
        (22.0, 17.6), (20.4, 21.5), (12.6, 21.5),
        (9.6, 18.6), (5.6, 14.6), (5.6, 12.9), (7.0, 12.2),
        (8.0, 12.6)]

HAND = [(x - 1.0, y) for (x, y) in HAND_ROH]

WIDTH = [(1.5, 12.0), (7.0, 7.2), (7.0, 10.3), (17.0, 10.3),
          (17.0, 7.2), (22.5, 12.0), (17.0, 16.8), (17.0, 13.7),
          (7.0, 13.7), (7.0, 16.8)]

HEIGHT = _rot(WIDTH, 90.0)

DIAG1 = _rot(WIDTH, 45.0)
DIAG2 = _rot(WIDTH, -45.0)

CROSS = [(12.0, 1.5), (16.0, 6.0), (13.5, 6.0), (13.5, 10.5),
         (18.0, 10.5), (18.0, 8.0), (22.5, 12.0), (18.0, 16.0),
         (18.0, 13.5), (13.5, 13.5), (13.5, 18.0), (16.0, 18.0),
         (12.0, 22.5), (8.0, 18.0), (10.5, 18.0), (10.5, 13.5),
         (6.0, 13.5), (6.0, 16.0), (1.5, 12.0), (6.0, 8.0),
         (6.0, 10.5), (10.5, 10.5), (10.5, 6.0), (8.0, 6.0)]

WAIT = [(6.5, 2.5), (17.5, 2.5), (17.5, 5.0), (13.3, 11.3),
          (13.3, 12.7), (17.5, 19.0), (17.5, 21.5), (6.5, 21.5),
          (6.5, 19.0), (10.7, 12.7), (10.7, 11.3), (6.5, 5.0)]

def _verboten():
    import math
    cx, cy, ro, ri, w, gap = 12.0, 12.0, 10.2, 7.2, 1.5, 0.45
    di = math.degrees(math.asin(w / ri))
    g = math.degrees(gap / ro)
    gi = math.degrees(gap / ri)
    def P(r, a):
        t = math.radians(a)
        return (cx + r * math.cos(t), cy + r * math.sin(t))
    def arc(r, a0, a1, n):
        return [P(r, a0 + (a1 - a0) * k / n) for k in range(n + 1)]
    pts = []
    pts += arc(ro, 45 + di + g, 225 + di, 12)
    pts += [P(ri, 225 + di), P(ri, 45 - di + 360)]
    pts += arc(ri, 405 - di, 225 + di + gi, 8)[1:]
    pts += arc(ro, 225 + di + g, 405 + di, 12)
    pts += [P(ri, 45 + di + 360), P(ri, 225 - di)]
    pts += arc(ri, 225 - di, 45 + di + gi, 8)[1:]
    return pts


VERBOTEN = _verboten()

KOPIE = [(10, 3), (14, 3), (14, 10), (21, 10), (21, 14), (14, 14), (14, 21), (10, 21), (10, 14), (3, 14), (3, 10), (10, 10)]
TARGET = [(10, 2.5), (14, 2.5), (14, 12.5), (17.5, 12.5), (12, 19), (6.5, 12.5), (10, 12.5)]

FORMEN = [
    ("pfeil",  (2.0, 2.0),   PFEIL),
    ("text",   (12.0, 12.0), TEXT),
    ("hand",   (8.3, 2.5),   HAND),
    ("breite", (12.0, 12.0), WIDTH),
    ("hoehe",  (12.0, 12.0), HEIGHT),
    ("diag1",  (12.0, 12.0), DIAG1),
    ("diag2",  (12.0, 12.0), DIAG2),
    ("kreuz",  (12.0, 12.0), CROSS),
    ("warten", (12.0, 12.0), WAIT),
    ("verboten", (12.0, 12.0), VERBOTEN),
    ("kopie", (12.0, 12.0), KOPIE),
    ("ziel", (12.0, 12.0), TARGET),
]


def _schnitt(p1, p2, p3, p4):
    def kreuz(o, a, b):
        return ((a[0] - o[0]) * (b[1] - o[1])
                - (a[1] - o[1]) * (b[0] - o[0]))
    d1 = kreuz(p3, p4, p1)
    d2 = kreuz(p3, p4, p2)
    d3 = kreuz(p1, p2, p3)
    d4 = kreuz(p1, p2, p4)
    return ((d1 > 1e-9 and d2 < -1e-9) or (d1 < -1e-9 and d2 > 1e-9)) and \
           ((d3 > 1e-9 and d4 < -1e-9) or (d3 < -1e-9 and d4 > 1e-9))


def check(name, hot, pts):
    fehler = []
    n = len(pts)
    if n < 3:
        fehler.append("weniger als drei Ecken")
    for (x, y) in pts:
        if x < -0.01 or y < -0.01 or x > G + 0.01 or y > G + 0.01:
            fehler.append("Ecke ausserhalb des Rasters: %.2f,%.2f" % (x, y))
    for i in range(n):
        for j in range(i + 1, n):
            if j == i or (i == 0 and j == n - 1) or j == i + 1:
                continue
            if _schnitt(pts[i], pts[(i + 1) % n], pts[j], pts[(j + 1) % n]):
                fehler.append("Kanten %d und %d kreuzen sich" % (i, j))
    a = 0.0
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        a = a + (x1 * y2 - x2 * y1)
    if abs(a) < 1.0:
        fehler.append("Flaeche ist null")
    if not (0 <= hot[0] <= G and 0 <= hot[1] <= G):
        fehler.append("Griffpunkt ausserhalb")
    return fehler, abs(a) / 2.0


def in_(pts, x, y):
    n = len(pts)
    ja = False
    j = n - 1
    for i in range(n):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y):
            if x < (xj - xi) * (y - yi) / (yj - yi) + xi:
                ja = not ja
        j = i
    return ja


def male(pts, groesse=24):
    S = 3
    zeilen = []
    for r in range(groesse):
        z = ""
        for c in range(groesse):
            t = 0
            for sy in range(S):
                for sx in range(S):
                    x = (c + (sx + 0.5) / S) * G / groesse
                    y = (r + (sy + 0.5) / S) * G / groesse
                    if in_(pts, x, y):
                        t = t + 1
            if t == S * S:
                z = z + "#"
            elif t > S * S / 2:
                z = z + "+"
            elif t > 0:
                z = z + "."
            else:
                z = z + " "
        zeilen.append(z)
    return zeilen


def board():
    kopf = []
    daten = []
    for (name, hot, pts) in FORMEN:
        kopf.append((len(daten), len(pts),
                     int(round(hot[0] * 4)), int(round(hot[1] * 4))))
        for (x, y) in pts:
            daten.append(int(round(x * 4)))
            daten.append(int(round(y * 4)))
    return kopf, daten


def esc(bs):
    return "".join("\\x%02x" % b for b in bs)


def bauen(ziel):
    kopf, daten = board()
    for b in daten:
        assert 0 <= b <= 255, b
    kb = []
    for (off, n, hx, hy) in kopf:
        assert off % 2 == 0
        assert off // 2 < 256 and n < 256
        kb += [off // 2, n, hx, hy]
    template = os.path.join(os.path.dirname(__file__), "cursor.fi.template")
    s = open(template, encoding="utf-8").read()
    s = s.replace("@@KOPF@@", esc(kb))
    s = s.replace("@@KOPFN@@", str(len(kb)))
    s = s.replace("@@PUNKTE@@", esc(daten))
    s = s.replace("@@PUNKTEN@@", str(len(daten)))
    s = s.replace("@@FORMEN@@", str(len(FORMEN)))
    open(ziel, "w", encoding="utf-8").write(s)
    print("%s geschrieben: %d Formen, %d Ecken, %d Oktette Tafel"
          % (ziel, len(FORMEN), len(daten) // 2, len(kb) + len(daten)))


def main():
    schlecht = 0
    for (name, hot, pts) in FORMEN:
        fehler, area = check(name, hot, pts)
        print("== %s: %d Ecken, Flaeche %.1f Einheiten, Griff %.1f,%.1f"
              % (name, len(pts), area, hot[0], hot[1]))
        for z in male(pts, 24):
            print("   |" + z + "|")
        for f in fehler:
            print("   FEHLER: " + f)
            schlecht += 1
    if "--bauen" in sys.argv:
        ziel = os.path.join(os.path.dirname(__file__), "..", "..",
                            "kernel", "zeiger.fi")
        bauen(os.path.normpath(ziel))
    if schlecht:
        print("%d Fehler" % schlecht)
        return 1
    print("all %d shapes pass the checks" % len(FORMEN))
    return 0


if __name__ == "__main__":
    sys.exit(main())
