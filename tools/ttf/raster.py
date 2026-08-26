#!/usr/bin/env python3
"""tools/ttf/raster.py -- TrueType lesen und rastern, ZWEITE Fassung.

`kernel/ttf.fi` ist die erste.  Dieses Programm ist die zweite, in einer
anderen Sprache, auf der anderen Seite der Platte -- derselbe Gedanke wie
bei `tools/osum/mkfs.py` und dem Dateisystem.  Es gibt hier nur einen
Grund fuer eine zweite Fassung, und der ist die MESSUNG:

    Ein Bildschirmfoto sagt ueber gerasterten Text nur dann etwas, wenn
    es etwas gibt, WOGEGEN man es haelt.  Runde K7 hielt die Textkonsole
    gegen die Bitmaske aus `kernel/font.fi` -- Bit fuer Bit.  Bei einer
    Kantenglaettung gibt es keine Bitmaske; es gibt einen Algorithmus.
    Also steht der Algorithmus zweimal da, und das Foto wird gegen die
    zweite Fassung gerechnet.

Deshalb ist hier JEDE Rechnung so geschrieben, wie sie in Firn steht --
ganzzahlig, mit denselben Verschiebungen und derselben Rundung.  Zwei
Stellen, an denen Python und Firn AUSEINANDERGEHEN, und beide sind hier
ausdruecklich behandelt:

  * `>>` ist in beiden Sprachen ein ARITHMETISCHES Schieben (es rundet
    nach unten, auch bei negativen Zahlen).  Nachgemessen an firnc:
    `(0-7) >> 1` ist -4, nicht -3.  Das darf also unveraendert stehen.
  * `/` schneidet in Firn zur NULL hin ab (`(0-7) / 2` ist -3), Pythons
    `//` rundet nach unten (-4).  Wo geteilt wird, steht deshalb `tdiv`.

DER ALGORITHMUS, in der Reihenfolge, in der er laeuft:

  1. Die Umrisse aus `glyf`: Punkte, Linien und QUADRATISCHE Bezier --
     TrueType hat keine kubischen.  Fehlende Punkte auf der Kurve werden
     als Mittelpunkt zweier Kontrollpunkte ergaenzt (die Kurzschreibweise
     des Formats).
  2. Alles in 26.6-Festkomma: `f26(v) = (v * scale) >> 10`, mit
     `scale = (px << 16) / upm`.  Eine Einheit ist 1/64 Bildpunkt.
  3. Jede Bezier in gerade Stuecke zerlegt.  Die Anzahl haengt an der
     Laenge des Kontrollzugs -- ganzzahlig, damit beide Fassungen
     dieselbe Anzahl waehlen.
  4. Fuellen mit der NICHTNULL-REGEL und 4x4 Unterabtastung: vier
     Abtastzeilen je Bildzeile, vier Abtastspalten je Bildpunkt, also
     siebzehn Deckungsstufen (0..16).  Daraus die Deckkraft
     `(cov * 255 + 8) / 16`.

Verwendung:
    raster.py info    <ttf>
    raster.py glyphe  <ttf> <px> <zeichen>        -- als Text ausgeben
    raster.py breite  <ttf> <px> <text>           -- Laufweite in 26.6
    raster.py zeile   <ttf> <px> <text>           -- die ganze Zeile
    raster.py summe   <ttf> <px> <zeichen>        -- die Pruefsumme
    raster.py vergleich <ttf> <mitschnitt>        -- gegen `ttfdump`
"""
import re
import struct
import sys

FIRST = 0x20
LAST = 0x7E


def u8(d, o):
    return d[o]


def u16(d, o):
    return struct.unpack_from(">H", d, o)[0]


def s16(d, o):
    return struct.unpack_from(">h", d, o)[0]


def u32(d, o):
    return struct.unpack_from(">I", d, o)[0]


def tdiv(n, d):
    """Ganzzahlige Division, zur Null hin abgeschnitten -- Firns `/`."""
    q = abs(n) // abs(d)
    if (n < 0) != (d < 0):
        return -q
    return q


# --------------------------------------------------------------- lesen

class Ttf:
    """Der Leser.  Wortgleich zu `kernel/ttf.fi`."""

    def __init__(self, roh):
        self.d = roh
        if len(roh) < 12:
            raise ValueError("zu kurz")
        if u32(roh, 0) != 0x00010000 and roh[:4] != b"true":
            raise ValueError("keine TrueType-Datei")
        n = u16(roh, 4)
        self.tab = {}
        for i in range(n):
            marke = roh[12 + 16 * i:16 + 16 * i].decode("latin1")
            off = u32(roh, 12 + 16 * i + 8)
            laenge = u32(roh, 12 + 16 * i + 12)
            self.tab[marke] = (off, laenge)
        head = self.tab["head"][0]
        self.upm = u16(roh, head + 18)
        self.locfmt = s16(roh, head + 50)
        hhea = self.tab["hhea"][0]
        self.ascent = s16(roh, hhea + 4)
        self.descent = s16(roh, hhea + 6)
        self.gap = s16(roh, hhea + 8)
        self.nhmetrics = u16(roh, hhea + 34)
        self.numglyphs = u16(roh, self.tab["maxp"][0] + 4)
        self.cmap_off = self._cmap4()
        self.kern_off, self.kern_paare = self._kern0()

    # -- cmap 4 --------------------------------------------------------
    def _cmap4(self):
        o = self.tab["cmap"][0]
        n = u16(self.d, o + 2)
        for i in range(n):
            pid = u16(self.d, o + 4 + 8 * i)
            eid = u16(self.d, o + 6 + 8 * i)
            sub = u32(self.d, o + 8 + 8 * i)
            if (pid, eid) in ((3, 1), (3, 0), (0, 3), (0, 4)):
                if u16(self.d, o + sub) == 4:
                    return o + sub
        raise ValueError("keine cmap im Format 4")

    def glyph_of(self, c):
        o = self.cmap_off
        segx2 = u16(self.d, o + 6)
        enden = o + 14
        anfaenge = enden + segx2 + 2
        deltas = anfaenge + segx2
        bereiche = deltas + segx2
        i = 0
        while i < segx2 // 2:
            if u16(self.d, enden + i * 2) >= c:
                break
            i += 1
        if i >= segx2 // 2:
            return 0
        a = u16(self.d, anfaenge + i * 2)
        if a > c:
            return 0
        ro = u16(self.d, bereiche + i * 2)
        dl = u16(self.d, deltas + i * 2)
        if ro == 0:
            return (c + dl) & 0xFFFF
        p = bereiche + i * 2 + ro + (c - a) * 2
        g = u16(self.d, p)
        if g == 0:
            return 0
        return (g + dl) & 0xFFFF

    # -- kern 0 --------------------------------------------------------
    def _kern0(self):
        if "kern" not in self.tab:
            return 0, 0
        o = self.tab["kern"][0]
        if u16(self.d, o) != 0 or u16(self.d, o + 2) < 1:
            return 0, 0
        deckung = u16(self.d, o + 8)
        if (deckung >> 8) != 0 or (deckung & 1) != 1:
            return 0, 0
        return o + 14, u16(self.d, o + 10)

    def kern(self, g1, g2):
        if self.kern_off == 0:
            return 0
        schluessel = (g1 << 16) | g2
        lo, hi = 0, self.kern_paare
        while lo < hi:
            m = (lo + hi) // 2
            p = self.kern_off + m * 6
            k = (u16(self.d, p) << 16) | u16(self.d, p + 2)
            if k == schluessel:
                return s16(self.d, p + 4)
            if k < schluessel:
                lo = m + 1
            else:
                hi = m
        return 0

    # -- loca / hmtx ---------------------------------------------------
    def loca(self, gid):
        o = self.tab["loca"][0]
        if self.locfmt == 0:
            return u16(self.d, o + gid * 2) * 2
        return u32(self.d, o + gid * 4)

    def advance(self, gid):
        h = self.tab["hmtx"][0]
        if gid >= self.nhmetrics:
            gid = self.nhmetrics - 1
        return u16(self.d, h + gid * 4)

    # -- glyf ----------------------------------------------------------
    def contours(self, gid, tiefe=0):
        """Die Umrisse als Listen von (x, y, auf_der_kurve), in Font-Einheiten."""
        a, b = self.loca(gid), self.loca(gid + 1)
        if b <= a:
            return []
        g = self.tab["glyf"][0] + a
        nc = s16(self.d, g)
        if nc < 0:
            return self._composite(g, tiefe)
        enden = [u16(self.d, g + 10 + i * 2) for i in range(nc)]
        npunkte = enden[-1] + 1 if nc else 0
        p = g + 10 + nc * 2
        anweisungen = u16(self.d, p)
        p += 2 + anweisungen
        flags = []
        while len(flags) < npunkte:
            f = u8(self.d, p)
            p += 1
            flags.append(f)
            if f & 8:
                w = u8(self.d, p)
                p += 1
                for _ in range(w):
                    flags.append(f)
        flags = flags[:npunkte]
        xs, x = [], 0
        for f in flags:
            if f & 2:
                dx = u8(self.d, p)
                p += 1
                x += dx if (f & 16) else -dx
            elif not (f & 16):
                x += s16(self.d, p)
                p += 2
            xs.append(x)
        ys, y = [], 0
        for f in flags:
            if f & 4:
                dy = u8(self.d, p)
                p += 1
                y += dy if (f & 32) else -dy
            elif not (f & 32):
                y += s16(self.d, p)
                p += 2
            ys.append(y)
        aus = []
        anfang = 0
        for e in enden:
            aus.append([(xs[i], ys[i], (flags[i] & 1) != 0)
                        for i in range(anfang, e + 1)])
            anfang = e + 1
        return aus

    def _composite(self, g, tiefe):
        if tiefe > 4:
            return []
        aus = []
        p = g + 10
        while True:
            flags = u16(self.d, p)
            gid = u16(self.d, p + 2)
            p += 4
            if flags & 1:
                dx, dy = s16(self.d, p), s16(self.d, p + 2)
                p += 4
            else:
                dx = struct.unpack_from(">b", self.d, p)[0]
                dy = struct.unpack_from(">b", self.d, p + 1)[0]
                p += 2
            if flags & 8:
                p += 2
            elif flags & 0x40:
                p += 4
            elif flags & 0x80:
                p += 8
            if not (flags & 2):          # ARGS_ARE_XY_VALUES fehlt
                dx = dy = 0
            for k in self.contours(gid, tiefe + 1):
                aus.append([(x + dx, y + dy, an) for (x, y, an) in k])
            if not (flags & 0x20):
                break
        return aus


# ----------------------------------------------------------- rastern

def f26(v, scale):
    """Font-Einheit -> 26.6.  `>>` rundet nach unten, in beiden Sprachen."""
    return (v * scale) >> 10


def scale_of(px, upm):
    return (px << 16) // upm


def flatten(punkte, scale):
    """Ein Umriss in 26.6 als Folge gerader Stuecke."""
    if not punkte:
        return []
    p = [(f26(x, scale), f26(y, scale), an) for (x, y, an) in punkte]
    # Anfangspunkt: der erste auf der Kurve, sonst der Mittelpunkt.
    start = None
    for i, (x, y, an) in enumerate(p):
        if an:
            start = i
            break
    if start is None:
        mx = (p[0][0] + p[-1][0]) >> 1
        my = (p[0][1] + p[-1][1]) >> 1
        p = [(mx, my, True)] + p
        start = 0
    p = p[start:] + p[:start]
    aus = [(p[0][0], p[0][1])]
    i = 1
    n = len(p)
    while i <= n:
        x, y, an = p[i % n]
        if an:
            aus.append((x, y))
            i += 1
            continue
        # ein Kontrollpunkt: der Endpunkt ist der naechste auf der Kurve
        # oder der Mittelpunkt zum naechsten Kontrollpunkt.
        nx, ny, nan = p[(i + 1) % n]
        if not nan:
            nx = (x + nx) >> 1
            ny = (y + ny) >> 1
            schritt = 1
        else:
            schritt = 2
        ax, ay = aus[-1]
        aus += quad(ax, ay, x, y, nx, ny)
        i += schritt
    return aus


def quad_stuecke(x0, y0, cx, cy, x1, y1):
    """Wie viele gerade Stuecke -- ganzzahlig und in beiden Fassungen gleich."""
    d = (abs(cx - x0) + abs(cy - y0) + abs(x1 - cx) + abs(y1 - cy))
    n = (d >> 6) // 3 + 2
    if n > 32:
        n = 32
    return n


def quad(x0, y0, cx, cy, x1, y1):
    n = quad_stuecke(x0, y0, cx, cy, x1, y1)
    aus = []
    for i in range(1, n + 1):
        j = n - i
        x = tdiv(j * j * x0 + 2 * j * i * cx + i * i * x1, n * n)
        y = tdiv(j * j * y0 + 2 * j * i * cy + i * i * y1, n * n)
        aus.append((x, y))
    return aus


class Glyphe:
    def __init__(self, w, h, links, oben, adv26, deckung):
        self.w, self.h = w, h
        self.links, self.oben = links, oben
        self.adv26 = adv26
        self.a = deckung            # h Zeilen zu w Oktetten, 0..255

    def punkt(self, x, y):
        if x < 0 or y < 0 or x >= self.w or y >= self.h:
            return 0
        return self.a[y * self.w + x]

    def gesetzt(self):
        return sum(1 for v in self.a if v > 0)

    def voll(self):
        return sum(1 for v in self.a if v >= 128)


def raster(f, gid, px):
    """Eine Glyphe rastern.  Das Ergebnis ist DIE Zusage dieser Runde."""
    scale = scale_of(px, f.upm)
    kanten = []
    for k in f.contours(gid):
        punkte = flatten(k, scale)
        for i in range(len(punkte)):
            ax, ay = punkte[i]
            bx, by = punkte[(i + 1) % len(punkte)]
            if ay != by:
                kanten.append((ax, ay, bx, by))
    adv26 = f26(f.advance(gid), scale)
    if not kanten:
        return Glyphe(0, 0, 0, 0, adv26, bytearray())

    minx = min(min(k[0], k[2]) for k in kanten)
    maxx = max(max(k[0], k[2]) for k in kanten)
    miny = min(min(k[1], k[3]) for k in kanten)
    maxy = max(max(k[1], k[3]) for k in kanten)
    bx0 = minx >> 6
    bx1 = (maxx + 63) >> 6
    by0 = miny >> 6
    by1 = (maxy + 63) >> 6
    w = bx1 - bx0
    h = by1 - by0
    if w <= 0 or h <= 0 or w > 512 or h > 512:
        return Glyphe(0, 0, 0, 0, adv26, bytearray())

    a = bytearray(w * h)
    for py in range(by0, by1):
        cov = [0] * w
        for sub in range(4):
            ys = py * 64 + 8 + sub * 16
            schnitte = []
            for (ax, ay, bx, by) in kanten:
                lo, hi = (ay, by) if ay < by else (by, ay)
                if ys < lo or ys >= hi:
                    continue
                xs = ax + tdiv((bx - ax) * (ys - ay), (by - ay))
                schnitte.append((xs, 1 if by > ay else -1))
            if not schnitte:
                continue
            schnitte.sort(key=lambda s: s[0])
            wind = 0
            anfang = 0
            for (xs, dz) in schnitte:
                vorher = wind
                wind += dz
                if vorher == 0 and wind != 0:
                    anfang = xs
                elif vorher != 0 and wind == 0:
                    j0 = (anfang - 8 + 15) >> 4
                    j1 = (xs - 8 + 15) >> 4
                    if j0 < bx0 * 4:
                        j0 = bx0 * 4
                    if j1 > bx1 * 4:
                        j1 = bx1 * 4
                    for j in range(j0, j1):
                        cov[(j >> 2) - bx0] += 1
        zeile = (by1 - 1 - py) * w
        for i in range(w):
            c = cov[i]
            if c > 16:
                c = 16
            a[zeile + i] = (c * 255 + 8) // 16
    return Glyphe(w, h, bx0, by1, adv26, a)


class Schrift:
    """Ein geladener Zeichensatz samt Glyphenspeicher."""

    def __init__(self, pfad, px):
        self.f = Ttf(open(pfad, "rb").read())
        self.px = px
        self.scale = scale_of(px, self.f.upm)
        self.speicher = {}

    def glyphe(self, c):
        if c in self.speicher:
            return self.speicher[c]
        g = raster(self.f, self.f.glyph_of(c), self.px)
        self.speicher[c] = g
        return g

    def aufsteiger(self):
        return f26(self.f.ascent, self.scale) >> 6

    def absteiger(self):
        return (0 - f26(self.f.descent, self.scale)) >> 6

    def zeilenhoehe(self):
        return (f26(self.f.ascent - self.f.descent + self.f.gap,
                    self.scale) + 63) >> 6

    def laufweite(self, text):
        """Die Zeile in 26.6, mit Unterschneidung."""
        x = 0
        vorher = 0
        for ch in text:
            c = ord(ch)
            gid = self.f.glyph_of(c)
            if vorher:
                x += f26(self.f.kern(vorher, gid), self.scale)
            x += f26(self.f.advance(gid), self.scale)
            vorher = gid
        return x

    def stellen(self, text):
        """(Zeichen, x-in-26.6) je Zeichen einer Zeile."""
        aus = []
        x = 0
        vorher = 0
        for ch in text:
            c = ord(ch)
            gid = self.f.glyph_of(c)
            if vorher:
                x += f26(self.f.kern(vorher, gid), self.scale)
            aus.append((c, x))
            x += f26(self.f.advance(gid), self.scale)
            vorher = gid
        return aus


# ------------------------------------------------------------ Befehle

def summe(g):
    """FNV-1a ueber die rohen Deckungswerte -- dieselbe Zeile wie
    `kmain.glyph_sum`."""
    acc = 2166136261
    for i in range(g.w * g.h):
        a = g.punkt(i % g.w, i // g.w)
        acc = ((acc ^ a) * 16777619) & 0xFFFFFFFF
    return acc


def vergleich(pfad_ttf, mitschnitt):
    """DIE ZUSAGE DIESER RUNDE UEBER DEN RASTERER.

    Der Kernel gibt auf das Wort `ttfdump` hin einige Glyphen als Text
    aus (`kmain.say_glyph`): Groesse, Lage, Laufweite, eine Pruefsumme
    ueber die rohen Deckungswerte und die Zeilen auf zehn Stufen
    gerundet.  Dieses Programm rastert dieselben Zeichen selbst und
    haelt ALLES dagegen.

    Zwei unabhaengige Fassungen desselben Algorithmus, in zwei Sprachen.
    Stimmen ihre Pruefsummen ueberein, ist der Kernel-Rasterer nicht
    "ungefaehr richtig", sondern gleich."""
    roh = open(mitschnitt, "rb").read().decode("latin1")
    faelle = re.findall(
        r"ttfglyph c=(\d+)\s+px=(\d+)\s+w=(\d+)\s+h=(\d+)\s+"
        r"left=(-?\d+)\s+top=(-?\d+)\s+adv=(\d+)\s+sum=(\d+)"
        r"((?:\s*\nttfrow \d+ \|.*\|)*)", roh)
    if not faelle:
        print("keine ttfglyph-Ausgabe im Mitschnitt")
        return 1
    stufen = " .:-=+*#%@"
    schriften = {}
    schlecht = []
    geprueft = 0
    tinte = 0
    for (c, px, w, h, left, top, adv, sm, zeilen) in faelle:
        c, px = int(c), int(px)
        if px not in schriften:
            schriften[px] = Schrift(pfad_ttf, px)
        g = schriften[px].glyphe(c)
        name = "'%c' (0x%02x)" % (c if 32 <= c < 127 else 63, c)
        geprueft += 1
        tinte += g.gesetzt()
        if (g.w, g.h, g.links, g.oben, g.adv26) != (int(w), int(h),
                                                    int(left), int(top),
                                                    int(adv)):
            schlecht.append("%s Masse: Kern %sx%s l=%s t=%s a=%s, "
                            "Wirt %dx%d l=%d t=%d a=%d"
                            % (name, w, h, left, top, adv, g.w, g.h,
                               g.links, g.oben, g.adv26))
            continue
        if summe(g) != int(sm):
            schlecht.append("%s Pruefsumme: Kern %s, Wirt %d"
                            % (name, sm, summe(g)))
            continue
        soll = [ "".join(stufen[min(9, g.punkt(x, y) * 10 // 256)]
                         for x in range(g.w)) for y in range(g.h) ]
        ist = re.findall(r"ttfrow \d+ \|(.*)\|", zeilen)
        if ist != soll:
            schlecht.append("%s Bildzeilen weichen ab" % name)
    print("%d Glyphen, %d Tintenpunkte: %d abweichend"
          % (geprueft, tinte, len(schlecht)))
    for z in schlecht[:8]:
        print("    " + z)
    return 1 if schlecht else 0



def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd = argv[1]
    if cmd == "info":
        f = Ttf(open(argv[2], "rb").read())
        print("upm=%d glyphen=%d asc=%d desc=%d gap=%d kern=%d tabellen=%s"
              % (f.upm, f.numglyphs, f.ascent, f.descent, f.gap,
                 f.kern_paare, ",".join(sorted(f.tab))))
        return 0
    if cmd == "glyphe":
        s = Schrift(argv[2], int(argv[3]))
        g = s.glyphe(ord(argv[4]))
        print("%dx%d links=%d oben=%d adv=%d/64 gesetzt=%d"
              % (g.w, g.h, g.links, g.oben, g.adv26, g.gesetzt()))
        stufen = " .:-=+*#%@"
        for y in range(g.h):
            print("".join(stufen[min(9, g.punkt(x, y) * 10 // 256)]
                          for x in range(g.w)))
        return 0
    if cmd == "summe":
        s = Schrift(argv[2], int(argv[3]))
        g = s.glyphe(ord(argv[4]))
        print(summe(g))
        return 0
    if cmd == "vergleich":
        return vergleich(argv[2], argv[3])
    if cmd == "breite":
        s = Schrift(argv[2], int(argv[3]))
        print("%d/64 = %d Bildpunkte" % (s.laufweite(argv[4]),
                                         s.laufweite(argv[4]) >> 6))
        return 0
    if cmd == "zeile":
        s = Schrift(argv[2], int(argv[3]))
        for (c, x) in s.stellen(argv[4]):
            print("%c bei %d/64" % (c, x))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
