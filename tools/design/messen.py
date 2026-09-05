#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/design/messen.py -- EINE OBERFLAECHE IN ZAHLEN, NICHT IN ADJEKTIVEN.

    messen.py <verzeichnis-einer-aufnahme> [--json <datei>]

"Wirkt altbacken" ist keine Messung und laesst sich nicht abnehmen.
Dieses Werkzeug beantwortet stattdessen sieben Fragen, die man
nachrechnen kann, aus zwei Quellen: den Rechtecken, die die Programme
selbst auf der seriellen Leitung melden (`wlib: text ...`, `launcher:
rect ...`, `settings: rect name=...`, `taskbar: ...`), und den
Bildpunkten der Aufnahmen.

  1. DAS RASTER.  Wie viele der gemeldeten Laengen (x, y, Breite, Hoehe)
     sind Vielfache von vier?  Ein Abstandssystem, das kein Raster hat,
     erkennt man daran, dass diese Zahl bei etwa einem Viertel liegt --
     dem Wert des Zufalls.

  2. DIE KLICKFLAECHEN.  Jede Hoehe eines Bedienelements, das man
     anfassen kann, gegen 32 Bildpunkte.  Fluent, HIG, Material und
     Adwaita sind sich hier ausnahmsweise einig; alles darunter wird auf
     einem Beruehrungsschirm zum Gluecksspiel.

  3. DIE ZEILENHOEHE.  Zeilenhoehe geteilt durch Schriftgroesse.  Unter
     1,3 klebt Text aneinander; die Skala der Entwurfssysteme geht von
     1,25 (eng, fuer Ueberschriften) bis 1,5 (Fliesstext).

  4. DIE ECKEN.  Der Radius, den ein Fenster WIRKLICH hat -- abgelesen an
     der Diagonale seiner oberen linken Ecke -- und wie viele
     Zwischenwerte dort stehen.  Null Zwischenwerte heisst: harte
     Treppe.  Das ist das, was eine Oberflaeche sofort billig aussehen
     laesst, und es ist einzeln messbar.

  5. DIE HOEHE.  Steht unter einem Fenster ein Schatten?  Gemessen als
     Helligkeitsabfall in dem Band unmittelbar unter der Unterkante,
     gegen den Schreibtisch daneben.

  6. DER TEXT.  Leere Beschriftungen, abgeschnittener Text,
     Ueberlappungen -- dieselben drei Fragen wie
     tools/themestore/shotcheck.py, hier ueber ALLE Aufnahmen einer
     Runde statt ueber eine.

  7. DIE FLAECHEN.  Wie viele verschiedene Farben hat das Bild, und wie
     viele davon tragen mehr als ein Promille der Flaeche?  Eine
     Oberflaeche ohne Hoehenstaffelung kommt mit sehr wenigen aus.

Alles, was hier herauskommt, ist eine Zahl mit einer Herkunft.  Wo eine
Frage aus den Daten nicht zu beantworten ist, steht das als `-` da und
nicht als 0.
"""
import glob
import json
import os
import re
import sys


# ------------------------------------------------------------ das Bild
def ppm(pfad):
    d = open(pfad, "rb").read()
    if not d.startswith(b"P6"):
        raise SystemExit("kein P6-PPM: %s" % pfad)
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
    return f[0], f[1], d[at:]


class Bild:
    def __init__(self, pfad):
        self.w, self.h, self.d = ppm(pfad)

    def px(self, x, y):
        if x < 0 or y < 0 or x >= self.w or y >= self.h:
            return None
        o = (y * self.w + x) * 3
        return (self.d[o], self.d[o + 1], self.d[o + 2])

    def farben(self):
        z = {}
        for i in range(0, len(self.d) - 2, 3):
            k = (self.d[i], self.d[i + 1], self.d[i + 2])
            z[k] = z.get(k, 0) + 1
        return z


# ---------------------------------------------------- die Meldungen
RE_TEXT = re.compile(
    r"wlib: text win=(\d+) kind=(\d+) x=(\d+) base=(\d+) fg=(\d+) bg=(\d+) "
    r"tw=(\d+) ax=(\d+) ay=(\d+) t=(.*)")
RE_RECT = re.compile(
    r"(\w+): rect (?:id=(\d+) kind=(\d+)|name=(\w+)) "
    r"x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
RE_TBF = re.compile(r"taskbar: (start|field \w+|btn i=\d+ id=\d+) "
                    r"x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
RE_FONT = re.compile(r"wlib: font ui px=(\d+) asc=(\d+) h=(\d+)")
RE_ZH = re.compile(r"rows x=\d+ base=\d+ zh=(\d+)")
RE_GEOM = re.compile(r"(\w+): geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
RE_SHAPE = re.compile(
    r"shape file=(\w+) name=(\w+) id=(\d+) keys=(\d+) ctrl_h=(\d+)")

# Welche Arten von Widgets kann man anfassen?  `wlib.NK_*`:
# 2 Knopf, 3 Kaestchen, 4 Eingabefeld, 5 Liste, 6 Tabelle, 7 Reiter,
# 9 Auswahl.  1 ist eine Beschriftung und 8 ein Trenner -- die zaehlen
# hier nicht mit, weil man sie nicht trifft.
FASSBAR = {2, 3, 4, 5, 6, 7, 9}


def lies(pfad):
    with open(pfad, "rb") as f:
        return f.read().decode("latin1")


def sammle(serial):
    t = lies(serial)
    rechtecke = []          # (quelle, art, x, y, w, h)
    for m in RE_RECT.finditer(t):
        quelle = m.group(1)
        art = int(m.group(3)) if m.group(3) else -1
        rechtecke.append((quelle, art, int(m.group(5)), int(m.group(6)),
                          int(m.group(7)), int(m.group(8))))
    for m in RE_TBF.finditer(t):
        was = m.group(1).split()[0]
        rechtecke.append(("taskbar", 2 if was in ("start", "btn") else -1,
                          int(m.group(2)), int(m.group(3)),
                          int(m.group(4)), int(m.group(5))))
    texte = []
    for m in RE_TEXT.finditer(t):
        texte.append(dict(win=m.group(1), kind=int(m.group(2)),
                          x=int(m.group(3)), base=int(m.group(4)),
                          fg=int(m.group(5)), bg=int(m.group(6)),
                          tw=int(m.group(7)), ax=int(m.group(8)),
                          ay=int(m.group(9)), t=m.group(10).rstrip("\r\n")))
    f = RE_FONT.search(t)
    font = (int(f.group(1)), int(f.group(2)), int(f.group(3))) if f else None
    zh = [int(m.group(1)) for m in RE_ZH.finditer(t)]
    geom = {}
    for m in RE_GEOM.finditer(t):
        geom[m.group(1)] = (int(m.group(2)), int(m.group(3)),
                            int(m.group(4)), int(m.group(5)))
    sh = RE_SHAPE.search(t)
    shape = (sh.group(2), int(sh.group(5))) if sh else None
    return rechtecke, texte, font, zh, geom, shape


# ------------------------------------------------------- die Messungen
def raster(rechtecke, n=4):
    """Wie viele gemeldete Laengen liegen auf dem n-Raster?"""
    gut = ges = 0
    schuldige = {}
    for quelle, _art, x, y, w, h in rechtecke:
        for wert, name in ((x, "x"), (y, "y"), (w, "w"), (h, "h")):
            ges += 1
            if wert % n == 0:
                gut += 1
            else:
                schuldige[quelle] = schuldige.get(quelle, 0) + 1
    return gut, ges, schuldige


def klickflaechen(rechtecke, mindest=32):
    zu_klein = []
    for quelle, art, _x, _y, w, h in rechtecke:
        if art in FASSBAR and h > 0 and h < mindest:
            zu_klein.append((quelle, art, w, h))
    return zu_klein


def eckfarben(b, x, y, n=16):
    """WIE VIELE VERSCHIEDENE FARBEN STEHEN IM ECKQUADRAT.

    Das ist die ehrlichste Zahl, die man ueber eine Ecke aus EINEM Bild
    lesen kann.  Eine harte, eckige Ecke kennt genau zwei Farben --
    Schreibtisch und Rahmen --, eine geglaettete Rundung kennt die
    Zwischenwerte der Deckung dazu.  Ein Radius in Bildpunkten laesst
    sich dagegen nicht zuverlaessig ablesen, solange der Schreibtisch
    ein VERLAUF ist: der Nachbarpunkt ist dort nie derselbe, und jede
    Schwelle findet entweder alles oder nichts.  (Der erste Versuch
    dieser Runde hat auf diese Weise dem eckigen Fenster einen Radius
    von 11 zugeschrieben.)
    """
    z = {}
    for dy in range(n):
        for dx in range(n):
            p = b.px(x + dx, y + dy)
            if p:
                z[p] = 1
    return len(z)


def eck_radius(b, x, y, hg, tol=24):
    """Der Radius der oberen linken Ecke bei (x, y), an der Diagonale
    abgelesen: wie viele Bildpunkte der Diagonale sind noch Hintergrund?
    Dazu die Zahl der ZWISCHENWERTE in dem Quadrat -- 0 heisst harte
    Treppe, also kein Antialiasing."""
    r = 0
    for i in range(0, 24):
        p = b.px(x + i, y + i)
        if p is None:
            break
        if max(abs(p[k] - hg[k]) for k in range(3)) > tol:
            r = i
            break
    zwischen = 0
    if r > 0:
        innen = b.px(x + r + 2, y + r + 2)
        if innen is not None:
            for dy in range(0, r + 3):
                for dx in range(0, r + 3):
                    p = b.px(x + dx, y + dy)
                    if p is None:
                        continue
                    dh = max(abs(p[k] - hg[k]) for k in range(3))
                    di = max(abs(p[k] - innen[k]) for k in range(3))
                    if dh > tol and di > tol:
                        zwischen += 1
    return r, zwischen


def schatten(b, x, y, w, h, tiefe=8):
    """Der Helligkeitsabfall im Band unter der Unterkante, gegen die
    Zeile `tiefe` weiter unten (die schon wieder Schreibtisch ist)."""
    def hell(p):
        return (p[0] * 299 + p[1] * 587 + p[2] * 114) // 1000
    unten = []
    ref = []
    for i in range(1, tiefe + 1):
        zeile = []
        for xx in range(x + w // 4, x + 3 * w // 4, 4):
            p = b.px(xx, y + h + i - 1)
            if p:
                zeile.append(hell(p))
        if zeile:
            unten.append(sum(zeile) // len(zeile))
    for xx in range(x + w // 4, x + 3 * w // 4, 4):
        p = b.px(xx, y + h + tiefe + 12)
        if p:
            ref.append(hell(p))
    if not unten or not ref:
        return None
    r = sum(ref) // len(ref)
    return [r - v for v in unten]


def entdoppeln(texte):
    """DIESELBE BESCHRIFTUNG ZAEHLT EINMAL.

    Die Programme melden ihre Texte bei JEDEM Neuzeichnen, und ein
    Schreibtisch zeichnet in dreissig Sekunden zwanzigmal neu.  Wer die
    Liste nimmt, wie sie ist, findet die Beschriftung `Suchen` zwanzigmal
    an derselben Stelle und meldet neunzehn Ueberlappungen, die es nicht
    gibt -- der erste Lauf dieser Runde hat auf diese Weise 12 273
    Ueberlappungen in einem Bild gefunden, auf dem gar kein Text
    ueberlappt.  Geschluesselt wird auf Fenster, Ort und Inhalt; der
    LETZTE Stand gewinnt, weil er der ist, der auf dem Bild steht.
    """
    d = {}
    for t in texte:
        d[(t["win"], t["ax"] + t["x"], t["ay"] + t["base"], t["t"])] = t
    return list(d.values())


def text_pruefung(b, texte, fenster=None):
    """Leere Beschriftung, abgeschnitten, ueberlappend -- die drei
    Fragen aus tools/themestore/shotcheck.py."""
    leer = ab = 0
    belegt = {}
    ueber = 0
    for tx in texte:
        if not tx["t"].strip():
            continue
        x0 = tx["ax"] + tx["x"]
        y0 = tx["ay"] + tx["base"] - 12
        w = max(tx["tw"], 1)
        bg = ((tx["bg"] >> 16) & 255, (tx["bg"] >> 8) & 255, tx["bg"] & 255)
        tinte = 0
        letzte = 0
        for yy in range(y0, y0 + 16):
            for xx in range(x0, x0 + w):
                p = b.px(xx, yy)
                if p is None:
                    continue
                if max(abs(p[k] - bg[k]) for k in range(3)) > 24:
                    tinte += 1
                    if xx >= x0 + w - 1:
                        letzte += 1
                    k = (xx, yy)
                    if k in belegt:
                        ueber += 1
                    belegt[k] = 1
        if tinte == 0:
            leer += 1
        if letzte > 0:
            ab += 1
    return leer, ab, ueber


def hauptfarben(b):
    z = b.farben()
    ges = b.w * b.h
    stark = sum(1 for n in z.values() if n * 1000 >= ges)
    return len(z), stark


# --------------------------------------------------------------- lauf
def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    d = sys.argv[1]
    serial = os.path.join(d, "serial.txt")
    if not os.path.exists(serial):
        print("kein serial.txt in %s" % d)
        return 1
    rechtecke, texte, font, zh, geom, shape = sammle(serial)

    erg = {}
    print("== %s ==" % d)
    if shape:
        print("form: %s  ctrl_h=%d" % shape)
        erg["shape"] = shape[0]
        erg["ctrl_h"] = shape[1]
    if font:
        print("schrift: px=%d ascent=%d hoehe=%d" % font)
        erg["font_px"], erg["font_h"] = font[0], font[2]

    gut, ges, schuldige = raster(rechtecke)
    p = (gut * 100 // ges) if ges else 0
    print("1. raster/4:      %d von %d Laengen (%d%%)" % (gut, ges, p))
    for q, n in sorted(schuldige.items(), key=lambda kv: -kv[1])[:6]:
        print("     daneben: %-10s %d" % (q, n))
    erg["raster4_gut"], erg["raster4_ges"], erg["raster4_prozent"] = gut, ges, p

    zk = klickflaechen(rechtecke)
    print("2. klickflaechen: %d von %d fassbaren Elementen unter 32 px"
          % (len(zk), sum(1 for r in rechtecke if r[1] in FASSBAR)))
    hoehen = sorted({r[5] for r in rechtecke if r[1] in FASSBAR})
    print("     Hoehen: %s" % (", ".join(str(v) for v in hoehen) or "-"))
    erg["klein32"] = len(zk)
    erg["hoehen"] = hoehen

    if zh and font:
        v = zh[-1] * 100 // font[0]
        print("3. listenzeile:   %d px bei %d px Schrift = %.2f"
              % (zh[-1], font[0], v / 100.0))
        erg["zeilenhoehe"], erg["zh_faktor"] = zh[-1], v / 100.0
    else:
        print("3. listenzeile:   -")

    bilder = sorted(glob.glob(os.path.join(d, "*.ppm")))
    erg["bilder"] = {}
    for pfad in bilder:
        name = os.path.basename(pfad)[:-4]
        b = Bild(pfad)
        e = {}
        n, stark = hauptfarben(b)
        e["farben"], e["farben_stark"] = n, stark
        # Die Ecke und der Schatten des Fensters, das dieses Bild zeigt.
        eig = pfad[:-4] + ".serial"
        g2 = geom
        if os.path.exists(eig):
            g2 = sammle(eig)[4]
        if "settings" not in g2:
            m = None
            for m in re.finditer(
                    r"settings: rect name=win x=(\d+) y=(\d+) w=(\d+) h=(\d+)",
                    lies(eig) if os.path.exists(eig) else ""):
                pass
            if m:
                g2 = dict(g2)
                g2["settings"] = tuple(int(m.group(i)) for i in (1, 2, 3, 4))
        prog = None
        for k in ("explorer", "settings", "launcher"):
            if k in g2:
                prog = k
                break
        if prog and prog in g2:
            # DIE ECKE UND DER SCHATTEN GEHOEREN DEM FENSTER UND NICHT
            # SEINER MALFLAECHE.  Ein Programm meldet mit `geom` das
            # Rechteck, in das es MALT; der Rahmen (2) und die
            # Titelleiste (22) liegen darum herum, und die runde Ecke
            # und der Schatten sind Sache des Zusammensetzers.  Der
            # erste Lauf dieser Runde hat den Schatten INNERHALB des
            # Fensters gesucht und ueberall 0 gefunden.
            gx, gy, gw, gh = g2[prog]
            gx = gx - 2 if gx >= 2 else 0
            gy = gy - 22 if gy >= 22 else 0
            gw, gh = gw + 4, gh + 24
            hg = b.px(max(gx - 8, 0), max(gy - 8, 0))
            e["eckfarben"] = eckfarben(b, gx, gy)
            if hg:
                r, zwi = eck_radius(b, gx, gy, hg)
                e["radius"], e["aa_punkte"] = r, zwi
            s = schatten(b, gx, gy, gw, gh)
            if s:
                e["schatten"] = s
        # Die Beschriftungen dieses Bildes und nicht die aller Bilder.
        if os.path.exists(eig):
            _r2, t2, _f2, _z2, _g2, _s2 = sammle(eig)
        else:
            t2 = texte
        leer, ab, ueber = text_pruefung(b, entdoppeln(t2))
        e["text_leer"], e["text_ab"], e["text_ueber"] = leer, ab, ueber
        erg["bilder"][name] = e
        print("   %-20s farben=%-5d tragend=%-3d eckfarben=%-4s "
              "schatten=%-16s leer=%d ab=%d ueber=%d"
              % (name, n, stark, e.get("eckfarben", "-"),
                 str(e.get("schatten", "-"))[:16], leer, ab, ueber))

    if "--json" in sys.argv:
        j = sys.argv[sys.argv.index("--json") + 1]
        with open(j, "w", encoding="utf-8") as f:
            json.dump(erg, f, indent=1, ensure_ascii=False)
        print("geschrieben: %s" % j)
    return 0


if __name__ == "__main__":
    sys.exit(main())
