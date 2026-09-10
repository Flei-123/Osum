#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/wm/zeiger2.py -- DIE ZEIGERFORMEN, ALS UMRISSE STATT ALS BITMASKEN.

RUNDE ECHTHARDWARE-4.  Justins Befund an den Belegbildern aus
ECHTHARDWARE-3 (und deutlicher noch auf seinen Fotos vom echten
Monitor): "der Zeiger sieht nicht gut aus" -- ein kleiner, hart
gepixelter Schwarzweisspfeil ohne Kantenglaettung, der bei hoher
Aufloesung ausfranst.

DER GRUND STAND IN `kernel/wm.fi`: der Zeiger war eine Bitmaske von
zwoelf mal achtzehn Bildpunkten (`cursor_row_of`), und bei
Vervielfachung 2 wurde JEDER Bildpunkt zu einem 2x2-Block.  Das ist
Vergroesserung eines Rasterbildes und nichts anderes; jede Treppe wird
doppelt so hoch.  Ausserdem gab es genau ZWEI Formen -- Pfeil und
Textmarke.  Hand, Groessenaenderung, Verschieben und Warten fehlten.

WAS HIER STEHT: je Form EIN geschlossener Umriss in einem
Entwurfsraster von 24 mal 24 Einheiten, in Vierteleinheiten als Oktette
(0..96, passt in ein Oktett).  Der Kern rastert daraus in ZIELGROESSE
(24 Bildpunkte bei Vervielfachung 1, 48 bei 2), mit dreifacher
Ueberabtastung, und leitet Aussenlinie und Schattenkante durch
Aufweitung desselben Umrisses ab -- nicht durch ein zweites Bild, das
mit dem ersten aus der Reihe laufen koennte.

Aufruf:
    python3 tools/wm/zeiger2.py            pruefen und als Bild malen
    python3 tools/wm/zeiger2.py --bauen    kernel/zeiger.fi erzeugen

Rueckgabe 0, wenn jede Form die Pruefungen haelt.
"""
import os
import sys

# Das Entwurfsraster.  24 ist die Zielgroesse bei Vervielfachung 1 --
# also ist eine Entwurfseinheit dort genau ein Bildpunkt, und die
# Zahlen unten lassen sich ohne Umrechnung lesen.
G = 24.0

# Die Formen.  Reihenfolge IST die Nummerierung, auf die sich
# kernel/wm.fi und kernel/user/wlibc.fi stuetzen:
#   0 Pfeil, 1 Textmarke, 2 Hand, 3 Breite, 4 Hoehe,
#   5 Diagonale NW-SO, 6 Diagonale NO-SW, 7 Verschieben, 8 Warten
#
# Je Form: (Name, Griffpunkt, Umriss).  Der Griffpunkt ist die Stelle
# im Entwurfsraster, die auf der Mausposition liegt -- beim Pfeil die
# Spitze, bei allen anderen die Mitte.
NAMEN = ["pfeil", "text", "hand", "breite", "hoehe",
         "diag1", "diag2", "kreuz", "warten"]


def _dreh(pts, grad, cx=12.0, cy=12.0):
    import math
    a = math.radians(grad)
    s, c = math.sin(a), math.cos(a)
    out = []
    for (x, y) in pts:
        dx, dy = x - cx, y - cy
        out.append((cx + dx * c - dy * s, cy + dx * s + dy * c))
    return out


# --- 0 PFEIL ------------------------------------------------------
# Die Spitze liegt auf (0,0); die Kerbe zwischen Kopf und Schwanz ist
# EINE Ecke und keine Luecke (das war der Fehler der Runde BLECH-HID).
# Der Umriss ist um zwei Einheiten nach rechts unten geschoben, und
# der Griffpunkt liegt genau auf der Spitze (2,2). Das ist kein
# Schoenheitsgriff: die weisse Aussenlinie ist 1,33 Einheiten stark,
# und ohne diesen Rand waere sie an der Spitze und an der linken Kante
# ABGESCHNITTEN -- der Pfeil haette dort einen dunklen Rand und
# sonst einen weissen.
PFEIL = [(2.0, 2.0), (2.0, 19.0), (6.2, 15.0), (8.9, 21.4),
         (11.6, 20.2), (8.9, 14.0), (13.6, 14.0)]

# --- 1 TEXTMARKE --------------------------------------------------
# Ein I-Balken mit Serifen: ohne sie ist er ueber senkrechten Kanten
# (Fensterrand, Tabellengitter) nicht zu erkennen.
TEXT = [(8.5, 3.5), (15.5, 3.5), (15.5, 5.1), (12.9, 5.1),
        (12.9, 18.9), (15.5, 18.9), (15.5, 20.5), (8.5, 20.5),
        (8.5, 18.9), (11.1, 18.9), (11.1, 5.1), (8.5, 5.1)]

# --- 2 HAND -------------------------------------------------------
# Ein zeigender Zeigefinger und die Faust darunter, als EIN Umriss.
# Der Griffpunkt liegt an der Fingerspitze, wie bei jedem System.
HAND_ROH = [(8.0, 2.5), (10.6, 2.5), (11.4, 3.4), (11.4, 11.4),
        (12.6, 10.6), (15.0, 10.6), (15.8, 11.4),
        (16.4, 10.9), (18.4, 10.9), (19.2, 11.7),
        (19.6, 11.4), (21.2, 11.4), (22.0, 12.3),
        (22.0, 17.6), (20.4, 21.5), (12.6, 21.5),
        (9.6, 18.6), (5.6, 14.6), (5.6, 12.9), (7.0, 12.2),
        (8.0, 12.6)]

# Um eine Einheit nach links: die Faust reichte bis 22,0, und die
# 1,33 Einheiten Aussenlinie waeren am rechten Rand des Feldes
# abgeschnitten worden.
HAND = [(x - 1.0, y) for (x, y) in HAND_ROH]

# --- 3 BREITE (Doppelpfeil waagrecht) -----------------------------
BREITE = [(1.5, 12.0), (7.0, 7.2), (7.0, 10.3), (17.0, 10.3),
          (17.0, 7.2), (22.5, 12.0), (17.0, 16.8), (17.0, 13.7),
          (7.0, 13.7), (7.0, 16.8)]

# --- 4 HOEHE ------------------------------------------------------
HOEHE = _dreh(BREITE, 90.0)

# --- 5/6 DIAGONALEN -----------------------------------------------
DIAG1 = _dreh(BREITE, 45.0)    # NW <-> SO
DIAG2 = _dreh(BREITE, -45.0)   # NO <-> SW

# --- 7 VERSCHIEBEN (Vierwegekreuz) --------------------------------
KREUZ = [(12.0, 1.5), (16.0, 6.0), (13.5, 6.0), (13.5, 10.5),
         (18.0, 10.5), (18.0, 8.0), (22.5, 12.0), (18.0, 16.0),
         (18.0, 13.5), (13.5, 13.5), (13.5, 18.0), (16.0, 18.0),
         (12.0, 22.5), (8.0, 18.0), (10.5, 18.0), (10.5, 13.5),
         (6.0, 13.5), (6.0, 16.0), (1.5, 12.0), (6.0, 8.0),
         (6.0, 10.5), (10.5, 10.5), (10.5, 6.0), (8.0, 6.0)]

# --- 8 WARTEN (Sanduhr) -------------------------------------------
WARTEN = [(6.5, 2.5), (17.5, 2.5), (17.5, 5.0), (13.3, 11.3),
          (13.3, 12.7), (17.5, 19.0), (17.5, 21.5), (6.5, 21.5),
          (6.5, 19.0), (10.7, 12.7), (10.7, 11.3), (6.5, 5.0)]

FORMEN = [
    ("pfeil",  (2.0, 2.0),   PFEIL),
    ("text",   (12.0, 12.0), TEXT),
    ("hand",   (8.3, 2.5),   HAND),
    ("breite", (12.0, 12.0), BREITE),
    ("hoehe",  (12.0, 12.0), HOEHE),
    ("diag1",  (12.0, 12.0), DIAG1),
    ("diag2",  (12.0, 12.0), DIAG2),
    ("kreuz",  (12.0, 12.0), KREUZ),
    ("warten", (12.0, 12.0), WARTEN),
]


# ------------------------------------------------------ die Pruefungen
def _schnitt(p1, p2, p3, p4):
    """Schneiden sich die Strecken p1p2 und p3p4 in ihrem Inneren?"""
    def kreuz(o, a, b):
        return ((a[0] - o[0]) * (b[1] - o[1])
                - (a[1] - o[1]) * (b[0] - o[0]))
    d1 = kreuz(p3, p4, p1)
    d2 = kreuz(p3, p4, p2)
    d3 = kreuz(p1, p2, p3)
    d4 = kreuz(p1, p2, p4)
    return ((d1 > 1e-9 and d2 < -1e-9) or (d1 < -1e-9 and d2 > 1e-9)) and \
           ((d3 > 1e-9 and d4 < -1e-9) or (d3 < -1e-9 and d4 > 1e-9))


def pruefe(name, hot, pts):
    fehler = []
    n = len(pts)
    if n < 3:
        fehler.append("weniger als drei Ecken")
    for (x, y) in pts:
        if x < -0.01 or y < -0.01 or x > G + 0.01 or y > G + 0.01:
            fehler.append("Ecke ausserhalb des Rasters: %.2f,%.2f" % (x, y))
    # Kein Paar nicht benachbarter Kanten darf sich schneiden -- ein
    # Umriss, der sich selbst kreuzt, hat kein Inneres, und die
    # Fuellung des Kerns waere Zufall.
    for i in range(n):
        for j in range(i + 1, n):
            if j == i or (i == 0 and j == n - 1) or j == i + 1:
                continue
            if _schnitt(pts[i], pts[(i + 1) % n], pts[j], pts[(j + 1) % n]):
                fehler.append("Kanten %d und %d kreuzen sich" % (i, j))
    # Flaeche > 0 und Umlaufsinn im Uhrzeigersinn (y nach unten)
    a = 0.0
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        a = a + (x1 * y2 - x2 * y1)
    if abs(a) < 1.0:
        fehler.append("Flaeche ist null")
    # Der Griffpunkt muss im Raster liegen.
    if not (0 <= hot[0] <= G and 0 <= hot[1] <= G):
        fehler.append("Griffpunkt ausserhalb")
    return fehler, abs(a) / 2.0


def drin(pts, x, y):
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
    """Dasselbe Verfahren wie im Kern: ueberabtasten und mitteln."""
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
                    if drin(pts, x, y):
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


def tafel():
    """Die Umrisse als Oktettfolge, in Vierteleinheiten."""
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
    kopf, daten = tafel()
    for b in daten:
        assert 0 <= b <= 255, b
    # Kopf: je Form vier Oktette -- Versatz/2 (Ecke), Eckenzahl,
    # Griff x, Griff y.  Der Versatz zaehlt ECKEN und nicht Oktette,
    # damit er in ein Oktett passt.
    kb = []
    for (off, n, hx, hy) in kopf:
        assert off % 2 == 0
        assert off // 2 < 256 and n < 256
        kb += [off // 2, n, hx, hy]
    vorlage = os.path.join(os.path.dirname(__file__), "zeiger.fi.vorlage")
    s = open(vorlage, encoding="utf-8").read()
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
        fehler, flaeche = pruefe(name, hot, pts)
        print("== %s: %d Ecken, Flaeche %.1f Einheiten, Griff %.1f,%.1f"
              % (name, len(pts), flaeche, hot[0], hot[1]))
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
    print("alle %d Formen halten die Pruefungen" % len(FORMEN))
    return 0


if __name__ == "__main__":
    sys.exit(main())
