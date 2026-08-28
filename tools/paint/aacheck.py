#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/paint/aacheck.py -- WIE GUT IST DIE KANTENGLAETTUNG WIRKLICH?
#
# DIE FRAGE, DIE DIESE RUNDE GESTELLT BEKAM, lautete: warum sieht das
# hier nicht aus wie Windows 11?  Eine der Antworten war "es gibt keine
# Kantenglaettung".  Das ist fuer die GLYPHEN falsch -- `kernel/ttf.fi`
# rastert seit Runde K10 mit 4x4-Unterabtastung -- und fuer die
# KANTEN DES FENSTERSERVERS richtig gewesen.  Beide Behauptungen sind
# hier nachgemessen statt geglaubt.
#
# WOGEGEN GEMESSEN WIRD.  `tools/ttf/raster.py` ist die zweite Fassung
# des Kernel-Rasterers, ganzzahlig und Zeile fuer Zeile gleich; sie ist
# die Fassung, gegen die alle Bildschirmfotos dieses Projekts gerechnet
# werden.  Als DRITTE, unabhaengige Instanz steht hier FreeType (ueber
# Pillow), also der Rasterer, den Linux, Android und jeder Browser
# benutzen.  FreeType rechnet die EXAKTE Flaechendeckung; das ist die
# Referenz, gegen die "4x4 Unterabtastung" eine Naeherung ist.
#
# WAS AUSGEWIESEN WIRD, je Zeichen und Groesse:
#
#   stufen    wie viele VERSCHIEDENE Deckungswerte im Zeichen vorkommen.
#             Ohne Glaettung sind es zwei (0 und 255).  Mit 4x4
#             Unterabtastung koennen es siebzehn sein, mit 8x8
#             fuenfundsechzig.
#   kante     dasselbe, aber nur entlang EINER senkrechten Bildzeile
#             durch die Schraege des Zeichens -- die Zahl, die man im
#             Bild sieht.
#   |d|       mittlere Abweichung je Bildpunkt gegen FreeType, in
#             Deckungsstufen 0..255, ueber die beste Ausrichtung der
#             beiden Bilder (+-2 Bildpunkte gesucht).
#   max       die groesste Abweichung eines einzelnen Bildpunktes.
#
#   ./tools/paint/aacheck.py [ttf] [--px 11,13,16,24] [--zeichen ABC]
#
# Ohne Pillow laeuft die Haelfte: die Stufenzaehlung braucht FreeType
# nicht, der Vergleich schon.  Das Skript sagt dann, was es nicht messen
# konnte, statt gruen zu melden.
import os
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.normpath(os.path.join(HIER, "..", ".."))
sys.path.insert(0, os.path.join(WURZEL, "tools", "ttf"))

import raster  # noqa: E402  -- die zweite Fassung des Kernel-Rasterers

try:
    from PIL import Image, ImageDraw, ImageFont
    HAT_PIL = True
except Exception:
    HAT_PIL = False


# ---------------------------------------------------------------- der
# EIGENE, EINSTELLBARE RASTERER.
#
# `tools/ttf/raster.py` rastert mit 4x4 Unterabtastung, genau wie
# `kernel/ttf.fi`.  Um zu MESSEN, wie weit vier mal vier von der
# Wahrheit entfernt sind, braucht es dieselbe Rechnung mit einer
# beliebigen Abtastdichte -- sonst vergleicht man zwei Rasterer, die
# sich in zehn Dingen unterscheiden (Kurvenzerlegung, Randkiste,
# Hinting), und weiss hinterher nicht, welches davon die Abweichung war.
#
# Diese Funktion ist Zeile fuer Zeile `raster.raster`, nur mit S statt
# der festen 4.  S muss 64 teilen (4, 8, 16, 32), damit die Abtastpunkte
# ganzzahlig auf dem 26.6-Raster liegen.  S = 32 ist mit 1025 Stufen so
# nah an der exakten Flaechendeckung, dass der Rest im Rauschen liegt --
# das ist hier die Referenz.
def raster_s(f, gid, px, S):
    schritt = 64 // S
    halb = schritt // 2
    scale = raster.scale_of(px, f.upm)
    kanten = []
    for k in f.contours(gid):
        punkte = raster.flatten(k, scale)
        for i in range(len(punkte)):
            ax, ay = punkte[i]
            bx, by = punkte[(i + 1) % len(punkte)]
            if ay != by:
                kanten.append((ax, ay, bx, by))
    if not kanten:
        return 0, 0, 0, 0, []
    minx = min(min(k[0], k[2]) for k in kanten)
    maxx = max(max(k[0], k[2]) for k in kanten)
    miny = min(min(k[1], k[3]) for k in kanten)
    maxy = max(max(k[1], k[3]) for k in kanten)
    bx0, bx1 = minx >> 6, (maxx + 63) >> 6
    by0, by1 = miny >> 6, (maxy + 63) >> 6
    w, h = bx1 - bx0, by1 - by0
    if w <= 0 or h <= 0:
        return 0, 0, 0, 0, []
    voll = S * S
    a = [0] * (w * h)
    for py in range(by0, by1):
        cov = [0] * w
        for sub in range(S):
            ys = py * 64 + halb + sub * schritt
            schnitte = []
            for (ax, ay, bx, by) in kanten:
                lo, hi = (ay, by) if ay < by else (by, ay)
                if ys < lo or ys >= hi:
                    continue
                xs = ax + raster.tdiv((bx - ax) * (ys - ay), (by - ay))
                schnitte.append((xs, 1 if by > ay else -1))
            if not schnitte:
                continue
            schnitte.sort(key=lambda t: t[0])
            wind = 0
            anfang = 0
            for (xs, dz) in schnitte:
                vorher = wind
                wind += dz
                if vorher == 0 and wind != 0:
                    anfang = xs
                elif vorher != 0 and wind == 0:
                    j0 = -((-(anfang - halb)) // schritt)
                    j1 = -((-(xs - halb)) // schritt)
                    if j0 < bx0 * S:
                        j0 = bx0 * S
                    if j1 > bx1 * S:
                        j1 = bx1 * S
                    for j in range(j0, j1):
                        cov[(j // S) - bx0] += 1
        zeile = (by1 - 1 - py) * w
        for i in range(w):
            c = cov[i]
            if c > voll:
                c = voll
            a[zeile + i] = (c * 255 + voll // 2) // voll
    return w, h, bx0, by1, a


def deckung_osum(schrift, px, zeichen):
    """Das Deckungsfeld, wie der Kernel es rastert.

    Gibt (w, h, links, oben, [Deckung 0..255]) -- Zeile fuer Zeile.
    """
    g = schrift.glyphe_px(zeichen, px) if hasattr(schrift, "glyphe_px") \
        else schrift.glyphe(zeichen)
    feld = []
    for r in range(g.h):
        for k in range(g.w):
            feld.append(g.punkt(k, r))
    return g.w, g.h, g.links, g.oben, feld


def deckung_freetype(pfad, px, zeichen):
    """Dasselbe Zeichen ueber FreeType, als Graustufenmaske."""
    f = ImageFont.truetype(pfad, px)
    m = f.getmask(zeichen, mode="L")
    w, h = m.size
    return w, h, [m.getpixel((x, y)) for y in range(h) for x in range(w)]


def stufen(feld):
    return len(set(feld))


def kantenstufen(w, h, feld):
    """Die meisten verschiedenen Werte in EINER senkrechten Bildzeile.

    Das ist die Zahl, die eine Schraege im Bild zeigt: wie viele
    Graustufen zwischen Tinte und Grund liegen.
    """
    best = 0
    for k in range(w):
        s = set(feld[r * w + k] for r in range(h))
        if len(s) > best:
            best = len(s)
    return best


def abweichung(aw, ah, af, bw, bh, bf):
    """Mittlere und groesste Abweichung ueber die beste Ausrichtung.

    Die beiden Rasterer setzen den Ursprung nicht zwingend gleich (die
    Rundung der Randkiste unterscheidet sich um bis zu einen Bildpunkt),
    also wird ueber -2..+2 in beiden Richtungen gesucht und die beste
    Ausrichtung genommen.  Alles, was ausserhalb liegt, zaehlt als
    Deckung 0 -- ein Bildpunkt, den nur EIN Rasterer setzt, ist ein
    Fehler und kein fehlendes Feld.
    """
    def hole(f, w, h, x, y):
        if x < 0 or y < 0 or x >= w or y >= h:
            return 0
        return f[y * w + x]

    bestes = None
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            summe = 0
            groesst = 0
            n = 0
            x0 = min(0, dx)
            y0 = min(0, dy)
            x1 = max(aw, bw + dx)
            y1 = max(ah, bh + dy)
            for y in range(y0, y1):
                for x in range(x0, x1):
                    a = hole(af, aw, ah, x, y)
                    b = hole(bf, bw, bh, x - dx, y - dy)
                    d = abs(a - b)
                    summe += d
                    if d > groesst:
                        groesst = d
                    n += 1
            if n == 0:
                continue
            wert = (summe / float(n), groesst, dx, dy)
            if bestes is None or wert[0] < bestes[0]:
                bestes = wert
    return bestes


def main():
    args = sys.argv[1:]
    pfad = os.path.join(WURZEL, "assets", "osum-sans.ttf")
    groessen = [11, 13, 16, 24]
    zeichen = "AOSgex8"
    i = 0
    rest = []
    while i < len(args):
        if args[i] == "--px":
            groessen = [int(v) for v in args[i + 1].split(",")]
            i += 2
        elif args[i] == "--zeichen":
            zeichen = args[i + 1]
            i += 2
        else:
            rest.append(args[i])
            i += 1
    if rest:
        pfad = rest[0]

    daten = open(pfad, "rb").read()
    print("PAINT-AA: %s, %d Oktette" % (os.path.relpath(pfad, WURZEL),
                                        len(daten)))
    if not HAT_PIL:
        print("   Pillow fehlt -- die Stufen werden gezaehlt, der "
              "Vergleich gegen FreeType nicht.")

    zusagen = 0
    fehler = 0
    alle_stufen = []
    alle_kanten = []
    alle_d = []
    alle_max = []
    dichte = {}          # S -> [summe, n, groesst]
    DICHTEN = [4, 8, 16]
    REF = 32

    for px in groessen:
        s = raster.Schrift(pfad, px)
        for c in zeichen:
            g = s.glyphe(ord(c))
            if g.w == 0 or g.h == 0:
                continue
            feld = [g.punkt(k, r) for r in range(g.h) for k in range(g.w)]
            st = stufen(feld)
            ka = kantenstufen(g.w, g.h, feld)
            alle_stufen.append(st)
            alle_kanten.append(ka)
            zeile = ("   px=%2d  '%s'  %2dx%-2d  stufen=%-3d kante=%-3d"
                     % (px, c, g.w, g.h, st, ka))
            if HAT_PIL:
                bw, bh, bf = deckung_freetype(pfad, px, c)
                mittel, groesst, dx, dy = abweichung(g.w, g.h, feld,
                                                     bw, bh, bf)
                alle_d.append(mittel)
                alle_max.append(groesst)
                zeile += ("  |d|=%6.2f  max=%3d  (versatz %+d,%+d)"
                          % (mittel, groesst, dx, dy))
            # DIE EIGENTLICHE MESSUNG DER NAEHERUNG: dieselbe Rechnung,
            # nur dichter abgetastet.  Randkiste und Kurvenzerlegung
            # sind identisch, also ist der Unterschied AUSSCHLIESSLICH
            # die Abtastdichte.
            gid = s.f.glyph_of(ord(c))
            rw, rh, _, _, rf = raster_s(s.f, gid, px, REF)
            for S in DICHTEN:
                aw2, ah2, _, _, af2 = raster_s(s.f, gid, px, S)
                if aw2 != rw or ah2 != rh:
                    continue
                e = dichte.setdefault(S, [0, 0, 0])
                for k in range(rw * rh):
                    d = abs(af2[k] - rf[k])
                    e[0] += d
                    e[1] += 1
                    if d > e[2]:
                        e[2] = d
            print(zeile)

    n = len(alle_stufen)
    if n == 0:
        print("PAINT-AA: kein Zeichen mit Umriss geprueft")
        return 1
    m_st = sum(alle_stufen) / float(n)
    m_ka = sum(alle_kanten) / float(n)
    print("PAINT-AA: %d Zeichen  stufen: min=%d mittel=%.1f max=%d"
          "   kante: min=%d mittel=%.1f max=%d"
          % (n, min(alle_stufen), m_st, max(alle_stufen),
             min(alle_kanten), m_ka, max(alle_kanten)))

    # ZUSAGE 1: es gibt ueberhaupt Graustufen.  Ohne Glaettung waeren es
    # zwei -- Tinte und Grund.
    if min(alle_stufen) > 2:
        print("  OK    jedes Zeichen hat mehr als zwei Deckungsstufen "
              "(kleinstes: %d)" % min(alle_stufen))
        zusagen += 1
    else:
        print("  FAIL  ein Zeichen hat nur %d Deckungsstufen -- das ist "
              "eine Bitmaske" % min(alle_stufen))
        fehler += 1

    # ZUSAGE 2: und zwar auch ENTLANG EINER KANTE, nicht nur irgendwo im
    # Zeichen.  Das ist die Zahl, die man sieht.
    if min(alle_kanten) >= 3:
        print("  OK    jede Kante traegt mindestens drei Stufen "
              "(kleinste: %d, mittlere: %.1f)"
              % (min(alle_kanten), m_ka))
        zusagen += 1
    else:
        print("  FAIL  eine Kante traegt nur %d Stufen" % min(alle_kanten))
        fehler += 1

    if HAT_PIL:
        md = sum(alle_d) / float(len(alle_d))
        print("PAINT-AA: gegen FreeType  |d| mittel=%.2f  "
              "schlechtestes Zeichen=%.2f  groesster Einzelfehler=%d"
              % (md, max(alle_d), max(alle_max)))
        # ZUSAGE 3: die Naeherung liegt im Mittel unter zehn
        # Deckungsstufen von 255 -- also unter vier Prozent.  Das ist
        # kein "sieht gleich aus", das ist eine Schranke.
        if md < 10.0:
            print("  OK    mittlere Abweichung gegen FreeType %.2f von "
                  "255 (%.2f Prozent)" % (md, 100.0 * md / 255.0))
            zusagen += 1
        else:
            print("  FAIL  mittlere Abweichung gegen FreeType %.2f von 255"
                  % md)
            fehler += 1

    # ---------------------------------------------------------------
    # DIE ABTASTDICHTE, GEGEN 32x32 GEMESSEN.
    if dichte:
        print("PAINT-AA: Abtastdichte gegen %dx%d (Referenz, %d Stufen)"
              % (REF, REF, REF * REF + 1))
        for S in sorted(dichte):
            summe, n, groesst = dichte[S]
            print("   %2dx%-2d  stufen=%-4d  |d|=%6.3f von 255 (%.3f%%)"
                  "  max=%3d  ueber %d Bildpunkte"
                  % (S, S, S * S + 1, summe / float(n),
                     100.0 * summe / float(n) / 255.0, groesst, n))
        if 4 in dichte and 8 in dichte:
            v4 = dichte[4][0] / float(dichte[4][1])
            v8 = dichte[8][0] / float(dichte[8][1])
            print("   8x8 ist %.2f mal genauer als 4x4" % (v4 / v8 if v8 else 0))

    print("PAINT-AA: %d Zusagen, %d Fehler" % (zusagen, fehler))
    return 1 if fehler else 0


if __name__ == "__main__":
    sys.exit(main())
