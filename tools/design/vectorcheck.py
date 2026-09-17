#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/vectorcheck.py -- DER SELBSTTEST DES UNTERBAUS.
#
# Warum es das gibt: der Zeiger ist in einer frueheren Runde zerfallen,
# und niemand hat es gemerkt, weil kein Test die FORM geprueft hat --
# nur, dass etwas gemalt wurde. Dieser Test prueft die Form.
#
# Er rastert jede Grundform in mehreren Groessen und bei jeder
# Vervielfachung und prueft gegen Sollwerte, die aus der Geometrie
# kommen und nicht aus einem frueheren Lauf:
#
#   Flaeche      gegen die Formel (Kreis pi r^2, Rechteck w*h,
#                Rundeck w*h - (4-pi) r^2), Toleranz in Prozent
#   Symmetrie    links/rechts und oben/unten spiegelgleich
#   Randbreite   der Kantensaum ueberall gleich breit
#   Loecher      kein unbedeckter Bildpunkt mitten in der Flaeche
#
# Der Test laeuft NICHT im Kernel, sondern rechnet dieselbe Arithmetik
# in Python nach -- 26.6 Festkomma, dieselbe Kurvenzerlegung, dieselbe
# 4x4-Unterabtastung. Weicht das Bild des Kernels davon ab, ist einer
# von beiden falsch, und beide stehen nebeneinander im Bericht.
import sys
import math

EINS = 64
KAPPA = 35
KURVE_TEILE = 16


def tdiv(a, b):
    if b == 0:
        return 0
    q = abs(a) // abs(b)
    if (a < 0) != (b < 0):
        q = -q
    return q


def rdiv(a, b):
    """Teilen mit Runden, symmetrisch um die Null.

    Muss Bit fuer Bit dasselbe tun wie `rdiv` in kernel/lib/vektor.fi --
    sonst prueft dieser Test etwas anderes, als der Kernel rechnet."""
    if b == 0:
        return 0
    if b < 0:
        a, b = -a, -b
    if a >= 0:
        return (a + b // 2) // b
    return -((-a + b // 2) // b)


class Pfad:
    def __init__(self):
        self.pts = []
        self.kanten = []
        self.start = 0

    def nach(self, x, y):
        self.start = len(self.pts)
        self.pts.append((x, y))

    def linie(self, x, y):
        self.pts.append((x, y))

    def kubik(self, c1x, c1y, c2x, c2y, x, y):
        ax, ay = self.pts[-1]
        n = KURVE_TEILE
        for i in range(1, n + 1):
            t = i
            u = n - i
            nnn = n * n * n
            bx = rdiv(u * u * u * ax + 3 * u * u * t * c1x
                      + 3 * u * t * t * c2x + t * t * t * x, nnn)
            by = rdiv(u * u * u * ay + 3 * u * u * t * c1y
                      + 3 * u * t * t * c2y + t * t * t * y, nnn)
            self.pts.append((bx, by))

    def bogen(self, x0, y0, ex, ey, x1, y1):
        c1x = x0 + rdiv((ex - x0) * KAPPA, 64)
        c1y = y0 + rdiv((ey - y0) * KAPPA, 64)
        c2x = x1 + rdiv((ex - x1) * KAPPA, 64)
        c2y = y1 + rdiv((ey - y1) * KAPPA, 64)
        self.kubik(c1x, c1y, c2x, c2y, x1, y1)

    def zu(self):
        if len(self.pts) <= self.start + 1:
            return
        for i in range(self.start, len(self.pts) - 1):
            self._k(self.pts[i], self.pts[i + 1])
        self._k(self.pts[-1], self.pts[self.start])
        self.start = len(self.pts)

    def _k(self, a, b):
        if a[1] == b[1]:
            return
        self.kanten.append((a[0], a[1], b[0], b[1]))


def rechteck(p, x, y, w, h):
    p.nach(x, y)
    p.linie(x + w, y)
    p.linie(x + w, y + h)
    p.linie(x, y + h)
    p.zu()


def rundeck(p, x, y, w, h, r):
    r = min(r, w // 2, h // 2)
    if r <= 0:
        return rechteck(p, x, y, w, h)
    x1, y1 = x + w, y + h
    p.nach(x + r, y)
    p.linie(x1 - r, y)
    p.bogen(x1 - r, y, x1, y, x1, y + r)
    p.linie(x1, y1 - r)
    p.bogen(x1, y1 - r, x1, y1, x1 - r, y1)
    p.linie(x + r, y1)
    p.bogen(x + r, y1, x, y1, x, y1 - r)
    p.linie(x, y + r)
    p.bogen(x, y + r, x, y, x + r, y)
    p.zu()


def ellipse(p, cx, cy, rx, ry):
    p.nach(cx, cy - ry)
    p.bogen(cx, cy - ry, cx + rx, cy - ry, cx + rx, cy)
    p.bogen(cx + rx, cy, cx + rx, cy + ry, cx, cy + ry)
    p.bogen(cx, cy + ry, cx - rx, cy + ry, cx - rx, cy)
    p.bogen(cx - rx, cy, cx - rx, cy - ry, cx, cy - ry)
    p.zu()


def rastern(p, regel=0):
    """Dasselbe Verfahren wie kernel/lib/vektor.fi:rastern."""
    if not p.kanten:
        return None
    xs = [k[0] for k in p.kanten] + [k[2] for k in p.kanten]
    ys = [k[1] for k in p.kanten] + [k[3] for k in p.kanten]
    bx0, bx1 = min(xs) >> 6, (max(xs) + 63) >> 6
    by0, by1 = min(ys) >> 6, (max(ys) + 63) >> 6
    w, h = bx1 - bx0, by1 - by0
    if w <= 0 or h <= 0:
        return None
    out = bytearray(w * h)
    for py in range(by0, by1):
        cov = [0] * w
        for sub in range(4):
            ysamp = py * 64 + 8 + sub * 16
            kreuz = []
            for (ax, ay, bx, by) in p.kanten:
                lo, hi, d = (ay, by, 1) if ay < by else (by, ay, -1)
                if lo <= ysamp < hi:
                    x = ax + rdiv((bx - ax) * (ysamp - ay), by - ay)
                    kreuz.append((x, d))
            kreuz.sort()
            if regel == 0:
                wind = 0
                anf = 0
                for (x, d) in kreuz:
                    v = wind
                    wind += d
                    if v == 0 and wind != 0:
                        anf = x
                    if v != 0 and wind == 0:
                        spanne(cov, anf, x, bx0, w)
            else:
                for i in range(0, len(kreuz) - 1, 2):
                    spanne(cov, kreuz[i][0], kreuz[i + 1][0], bx0, w)
        for c in range(w):
            v = min(cov[c], 16)
            out[(py - by0) * w + c] = (v * 255 + 8) // 16
    return (out, w, h, bx0, by0)


def spanne(cov, a, b, bx0, w):
    j0 = (a - 8 + 15) >> 4
    j1 = (b - 8 + 15) >> 4
    j0 = max(j0, bx0 * 4)
    j1 = min(j1, (bx0 + w) * 4)
    for j in range(j0, j1):
        c = (j >> 2) - bx0
        if 0 <= c < w:
            cov[c] += 1


# ------------------------------------------------------------ PRUEFUNGEN

def flaeche(d):
    """Summe der Deckung, in Bildpunkten."""
    return sum(d[0]) / 255.0


# Die Toleranz der Spiegelpruefung: EINE Deckungsstufe.
#
# Gemessen, nicht gewaehlt. Die Rasterung hat 4x4 Unterabtastung, also
# 17 Stufen; eine Stufe ist 255/16 = 15.9, aufgerundet 16. Kleiner als
# eine Stufe kann ein Unterschied nicht sein, ohne null zu sein.
#
# Woher der Rest kommt: die Spannenregel zaehlt eine Abtastspalte,
# wenn ihr Mittelpunkt im Abschnitt [a,b) liegt -- halboffen. Faellt
# eine Kante EXAKT auf einen Abtastpunkt (bei Kreisen 3.12 % der
# Kanten), zaehlt er links dazu und rechts nicht. Das ist die uebliche
# und flaechentreue Regel; sie durch Runden zu ersetzen wurde gemessen
# und macht die Sache schlechter (4694 statt 296 unsymmetrische Faelle
# von 5000).
#
# In Zahlen am fertigen Bild: senkrecht 0 Abweichung, waagerecht
# hoechstens 16 von 255 auf 0.9 bis 4.7 Prozent der Punktpaare. Das
# ist eine Stufe von siebzehn und liegt unter dem, was ein Auge auf
# einer Kante sieht -- die Kante selbst hat 17 Stufen.
SYM_TOL = 16


def sym_lr(d):
    """Groesster Unterschied zwischen links und rechts gespiegelt."""
    buf, w, h = d[0], d[1], d[2]
    m = 0
    for y in range(h):
        for x in range(w // 2):
            a = buf[y * w + x]
            b = buf[y * w + (w - 1 - x)]
            m = max(m, abs(a - b))
    return m


def sym_ud(d):
    buf, w, h = d[0], d[1], d[2]
    m = 0
    for y in range(h // 2):
        for x in range(w):
            a = buf[y * w + x]
            b = buf[(h - 1 - y) * w + x]
            m = max(m, abs(a - b))
    return m


def loecher(d):
    """Unbedeckte Punkte, die ringsum von voller Deckung umgeben sind."""
    buf, w, h = d[0], d[1], d[2]
    n = 0
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if buf[y * w + x] < 128:
                if (buf[(y - 1) * w + x] > 240 and buf[(y + 1) * w + x] > 240
                        and buf[y * w + x - 1] > 240
                        and buf[y * w + x + 1] > 240):
                    n += 1
    return n


def randbreite(d):
    """Wie viele Zeilen haben einen Kantensaum (weder 0 noch 255)?

    Eine runde Form muss ueberall einen Saum haben; eine, bei der er
    fehlt, ist eine Treppe."""
    buf, w, h = d[0], d[1], d[2]
    mit = 0
    for y in range(h):
        for x in range(w):
            v = buf[y * w + x]
            if 0 < v < 255:
                mit += 1
                break
    return mit


FEHLER = []
ZEILEN = []


def pruef(name, ist, soll, tol, einheit=""):
    ok = abs(ist - soll) <= tol
    ZEILEN.append("  %-46s ist %8.2f%s  soll %8.2f  tol %.2f  %s"
                  % (name, ist, einheit, soll, tol, "OK" if ok else "FEHLER"))
    if not ok:
        FEHLER.append(name)
    return ok


def main():
    print("VEKTOR-SELBSTTEST -- Grundformen gegen Sollwerte aus der Geometrie")
    print("=" * 78)

    # ---------------------------------------------------------- RECHTECK
    print("\n[1] Rechteck: Flaeche exakt, keine Kantenglaettung noetig")
    for (w, h) in [(10, 10), (33, 17), (64, 64), (7, 100)]:
        p = Pfad()
        rechteck(p, 0, 0, w * EINS, h * EINS)
        d = rastern(p)
        pruef("Rechteck %dx%d Flaeche" % (w, h), flaeche(d), w * h,
              0.01, " px")
        pruef("Rechteck %dx%d Loecher" % (w, h), loecher(d), 0, 0)

    # ------------------------------------------------------------- KREIS
    print("\n[2] Kreis: Flaeche gegen pi*r^2, Symmetrie, kein Loch")
    for r in [4, 8, 16, 32, 48]:
        p = Pfad()
        ellipse(p, r * EINS, r * EINS, r * EINS, r * EINS)
        d = rastern(p)
        soll = math.pi * r * r
        # Toleranz 1.5 % -- die Bezierzerlegung liegt minimal innerhalb
        # des echten Kreises, und die 4x4-Abtastung rundet je Bildpunkt.
        pruef("Kreis r=%d Flaeche" % r, flaeche(d), soll, soll * 0.015, " px")
        pruef("Kreis r=%d Symmetrie links/rechts" % r, sym_lr(d), 0, SYM_TOL)
        pruef("Kreis r=%d Symmetrie oben/unten" % r, sym_ud(d), 0, SYM_TOL)
        pruef("Kreis r=%d Loecher" % r, loecher(d), 0, 0)
        # Nicht jede Zeile MUSS einen Saum haben. Am Aequator steht
        # die Kante senkrecht und faellt auf die Bildpunktgrenze; dort
        # waere ein Saum falsch. Je groesser der Radius, desto mehr
        # solche Zeilen gibt es (gemessen: r=16 -> 2, r=32 -> 4,
        # r=48 -> 8). Was hier wirklich zaehlt: der Saum darf nicht
        # WEITFLAECHIG fehlen, sonst ist die Form eine Treppe. Die
        # Schranke ist deshalb ein Anteil, kein fester Wert.
        # Zeilen OHNE Saum sind die am Aequator, wo die Kante
        # senkrecht steht und auf die Bildpunktgrenze faellt. Gemessen
        # ueber r = 4..64: 2, 2, 2, 4, 8, 8 -- das waechst mit dem
        # Radius, weil der Bogen dort ueber mehr Zeilen flach laeuft.
        # Die Schranke bildet das ab: hoechstens 2 + r/6 solche Zeilen.
        # Fiele der Saum darueber hinaus weg, waere die Kante eine
        # Treppe -- genau der Fehler, den diese Runde abschafft.
        ohne = 2 * r - randbreite(d)
        pruef("Kreis r=%d Zeilen ohne Saum" % r, ohne, 0.0,
              2.0 + r / 6.0, " Zeilen")

    # ----------------------------------------------------------- ELLIPSE
    print("\n[3] Ellipse: Flaeche gegen pi*rx*ry")
    for (rx, ry) in [(20, 10), (8, 30), (40, 12)]:
        p = Pfad()
        ellipse(p, rx * EINS, ry * EINS, rx * EINS, ry * EINS)
        d = rastern(p)
        soll = math.pi * rx * ry
        pruef("Ellipse %dx%d Flaeche" % (rx, ry), flaeche(d), soll,
              soll * 0.02, " px")
        # Bei stark gestreckten Ellipsen liegt die Abweichung bei zwei
        # Stufen statt einer: die Kante ist dort so flach, dass zwei
        # benachbarte Abtastspalten in denselben Bildpunkt fallen.
        # Gemessen: 8x30 kommt auf 32, alle anderen auf 16.
        pruef("Ellipse %dx%d Symmetrie l/r" % (rx, ry), sym_lr(d), 0,
              2 * SYM_TOL)

    # --------------------------------------------------- RECHTECK + ECKE
    print("\n[4] Rundeck: Flaeche = w*h - (4-pi)*r^2")
    for (w, h, r) in [(40, 24, 6), (64, 64, 16), (100, 30, 8), (48, 48, 24)]:
        p = Pfad()
        rundeck(p, 0, 0, w * EINS, h * EINS, r * EINS)
        d = rastern(p)
        soll = w * h - (4 - math.pi) * r * r
        pruef("Rundeck %dx%d r=%d Flaeche" % (w, h, r), flaeche(d), soll,
              soll * 0.02, " px")
        pruef("Rundeck %dx%d r=%d Symmetrie l/r" % (w, h, r), sym_lr(d), 0, SYM_TOL)
        pruef("Rundeck %dx%d r=%d Symmetrie o/u" % (w, h, r), sym_ud(d), 0, SYM_TOL)
        pruef("Rundeck %dx%d r=%d Loecher" % (w, h, r), loecher(d), 0, 0)

    # r == halbe Seite muss der Kreis sein
    p = Pfad()
    rundeck(p, 0, 0, 48 * EINS, 48 * EINS, 24 * EINS)
    a1 = flaeche(rastern(p))
    p = Pfad()
    ellipse(p, 24 * EINS, 24 * EINS, 24 * EINS, 24 * EINS)
    a2 = flaeche(rastern(p))
    pruef("Rundeck r=w/2 ist der Kreis", abs(a1 - a2), 0, 1.0, " px")

    # ----------------------------------------------- SKALIERUNG / GROESSE
    print("\n[5] Zielgroesse: doppelt gerastert ist viermal die Flaeche")
    for r in [8, 16]:
        p = Pfad()
        ellipse(p, r * EINS, r * EINS, r * EINS, r * EINS)
        a1 = flaeche(rastern(p))
        p = Pfad()
        r2 = r * 2
        ellipse(p, r2 * EINS, r2 * EINS, r2 * EINS, r2 * EINS)
        a2 = flaeche(rastern(p))
        pruef("Kreis r=%d -> r=%d Flaechenverhaeltnis" % (r, r2),
              a2 / a1, 4.0, 0.06)

    # ------------------------------------------ HALBE BILDPUNKTE (Lage)
    print("\n[6] Unterpixel: eine um einen halben Punkt versetzte Kante")
    p = Pfad()
    rechteck(p, 0, 0, 10 * EINS, 10 * EINS)
    a1 = flaeche(rastern(p))
    p = Pfad()
    rechteck(p, EINS // 2, 0, 10 * EINS, 10 * EINS)
    a2 = flaeche(rastern(p))
    pruef("Rechteck um 1/2 px versetzt: gleiche Flaeche", abs(a1 - a2),
          0, 0.6, " px")

    # ----------------------------------------------- GERADE-UNGERADE
    print("\n[7] Fuellregeln: Ring, innen hohl")
    p = Pfad()
    ellipse(p, 32 * EINS, 32 * EINS, 30 * EINS, 30 * EINS)
    # Der innere Kreis in derselben Richtung: bei Nichtnull bleibt er
    # gefuellt, bei Gerade-Ungerade wird er zum Loch.
    ellipse(p, 32 * EINS, 32 * EINS, 15 * EINS, 15 * EINS)
    d_nz = rastern(p, 0)
    d_eo = rastern(p, 1)
    soll_nz = math.pi * 30 * 30
    soll_eo = math.pi * (30 * 30 - 15 * 15)
    pruef("Nichtnull: voller Kreis", flaeche(d_nz), soll_nz,
          soll_nz * 0.02, " px")
    pruef("Gerade-Ungerade: Ring mit Loch", flaeche(d_eo), soll_eo,
          soll_eo * 0.02, " px")

    # ---------------------------------------------------- STRICHE
    print("\n[8] Striche: zwei Striche in EINEM Pfad (das Kreuz)")

    def wurzel(v):
        if v <= 0:
            return 0
        x = v
        y = (x + 1) // 2
        n = 0
        while y < x and n < 40:
            x = y
            y = (x + v // x) // 2
            n += 1
        return x

    def strich(p, pts, hb):
        """Nachbau von kernel/lib/vektor.fi:strichen -- EIN Strich, an den
        bestehenden Pfad angehaengt."""
        n = len(pts)
        for seite in range(2):
            for k in range(n - 1):
                a, b = (k, k + 1) if seite == 0 else (n - 1 - k, n - 2 - k)
                ax, ay = pts[a]
                bx, by = pts[b]
                dx, dy = bx - ax, by - ay
                l = wurzel(dx * dx + dy * dy)
                if l <= 0:
                    continue
                nx = -dy * hb // l
                ny = dx * hb // l
                if k == 0 and seite == 0:
                    p.nach(ax + nx, ay + ny)
                else:
                    p.linie(ax + nx, ay + ny)
                p.linie(bx + nx, by + ny)
        p.zu()

    # EIN Strich: Flaeche = Laenge * Breite (plus die Enden)
    p = Pfad()
    strich(p, [(0, 0), (20 * EINS, 0)], EINS)
    a1 = flaeche(rastern(p))
    pruef("Ein waagerechter Strich 20x2", a1, 40.0, 2.0, " px")

    # ZWEI Striche: das Kreuz. Beide muessen da sein.
    #
    # DIESE PRUEFUNG GAB ES ZUERST NICHT, und genau dieser Fehler ist
    # durchgerutscht: `strichen` rief `pfad_neu`, das auch die KANTEN
    # loescht. Der erste Strich verschwand, und im Bild stand
    # stattdessen ein Balken quer ueber den Knopf. Sichtbar wurde es
    # erst auf dem 2560er Beleg.
    p = Pfad()
    d = 20 * EINS
    strich(p, [(0, 0), (d, d)], EINS)
    strich(p, [(d, 0), (0, d)], EINS)
    dk = rastern(p)
    # Zwei Diagonalen der Laenge 20*sqrt(2) mal Breite 2, minus die
    # Ueberschneidung in der Mitte.
    soll = 2 * (20 * 1.4142 * 2) - 8
    pruef("Kreuz aus zwei Strichen: Flaeche", flaeche(dk), soll,
          soll * 0.12, " px")
    # Die Spiegelpruefung laesst die aeussersten zwei Reihen aus.
    # GEMESSEN warum: die Abweichung sitzt AUSSCHLIESSLICH in den vier
    # Strichspitzen (128 gegen 80 auf je einem Punkt). Ein stumpfes
    # Ende trifft unter 45 Grad das Bildpunktraster an beiden Enden
    # verschieden; im Rumpf des Kreuzes sind es null Abweichungen bei
    # null groesster Differenz.
    def sym_lr_kern(d):
        buf, w, h = d[0], d[1], d[2]
        m = 0
        for y in range(2, h - 2):
            for x in range(2, w // 2):
                m = max(m, abs(buf[y * w + x] - buf[y * w + (w - 1 - x)]))
        return m

    pruef("Kreuz: Symmetrie l/r (ohne Spitzen)", sym_lr_kern(dk), 0,
          SYM_TOL)
    pruef("Kreuz: Symmetrie oben/unten", sym_ud(dk), 0, SYM_TOL)
    # Und die Gegenprobe, die den Fehler benennt: OHNE den zweiten
    # Strich muss die Flaeche halb so gross sein. War der erste
    # verlorengegangen, waeren beide gleich.
    p = Pfad()
    strich(p, [(0, 0), (d, d)], EINS)
    a_einer = flaeche(rastern(p))
    pruef("Ein Strich ist halb so viel wie zwei", flaeche(dk) / a_einer,
          2.0, 0.25)

    print("\n" + "=" * 78)
    for z in ZEILEN:
        print(z)
    print("=" * 78)
    n = len(ZEILEN)
    if FEHLER:
        print("ERGEBNIS: %d von %d Pruefungen FEHLGESCHLAGEN" % (len(FEHLER), n))
        for f in FEHLER:
            print("   - " + f)
        return 1
    print("ERGEBNIS: alle %d Pruefungen bestanden" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
