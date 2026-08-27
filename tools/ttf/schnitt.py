#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/ttf/schnitt.py -- eine TrueType-Datei auf das Noetige zusammenschneiden.

Runde K10 liest im Kernel echte TrueType-Umrisse (`kernel/ttf.fi`).  Eine
vollstaendige DejaVu-Datei ist 760 KiB gross und traegt 6253 Glyphen,
zwanzig Tabellen, Hinting-Programme und eine Mathematiktabelle -- davon
braucht ein Rasterer genau sieben Tabellen und fuenfundneunzig Glyphen.
Dieses Programm schneidet die Datei darauf zusammen:

    head  Einheiten je Geviert, das Format von `loca`
    hhea  Aufsteiger, Absteiger, Zeilenabstand, Zahl der Laufweiten
    maxp  wie viele Glyphen es sind
    hmtx  Laufweite und linker Seitenabstand je Glyphe
    cmap  Zeichen -> Glyphennummer (Format 4)
    loca  Glyphennummer -> Versatz in `glyf`
    glyf  die Umrisse selbst
    kern  Unterschneidung, Format 0 (nur wenn die Vorlage eine hat)

REPRODUZIERBAR UND OHNE FREMDE BIBLIOTHEK.  Kein fontTools, kein
FreeType -- reines `struct`.  Das ist Absicht und derselbe Gedanke wie
bei `tools/osum/mkfs.py`: die Datei, die der Kernel liest, wird auf dem
Wirt von einem ZWEITEN Programm erzeugt, das dasselbe Format aus der
Spezifikation heraus versteht.  Sind sich beide nicht einig, faellt es
sofort auf -- ein Umriss an der falschen Stelle ist im Bild zu sehen.

Verwendung:
    schnitt.py <vorlage.ttf> <ziel.ttf> [erstes] [letztes]

Vorgabe fuer den Bereich ist 0x20..0x7E, also derselbe wie beim
8x16-Zeichensatz aus Runde K7 (`kernel/font.fi`).
"""
import struct
import sys


def u16(d, o):
    return struct.unpack_from(">H", d, o)[0]


def s16(d, o):
    return struct.unpack_from(">h", d, o)[0]


def u32(d, o):
    return struct.unpack_from(">I", d, o)[0]


class Vorlage:
    def __init__(self, pfad):
        self.d = open(pfad, "rb").read()
        if self.d[:4] not in (b"\x00\x01\x00\x00", b"true"):
            raise SystemExit("schnitt: %s ist keine TrueType-Datei" % pfad)
        n = u16(self.d, 4)
        self.tab = {}
        for i in range(n):
            marke, _, off, laenge = struct.unpack_from(">4sIII", self.d,
                                                       12 + 16 * i)
            self.tab[marke.decode("latin1")] = (off, laenge)
        for m in ("head", "hhea", "maxp", "hmtx", "cmap", "loca", "glyf"):
            if m not in self.tab:
                raise SystemExit("schnitt: Tabelle '%s' fehlt" % m)
        head = self.tab["head"][0]
        self.upm = u16(self.d, head + 18)
        self.locfmt = s16(self.d, head + 50)
        self.numglyphs = u16(self.d, self.tab["maxp"][0] + 4)
        self.nhmetrics = u16(self.d, self.tab["hhea"][0] + 34)
        self.ascent = s16(self.d, self.tab["hhea"][0] + 4)
        self.descent = s16(self.d, self.tab["hhea"][0] + 6)
        self.gap = s16(self.d, self.tab["hhea"][0] + 8)

    # ------------------------------------------------------------ loca
    def loca(self, gid):
        off = self.tab["loca"][0]
        if self.locfmt == 0:
            return u16(self.d, off + gid * 2) * 2
        return u32(self.d, off + gid * 4)

    def glyph_bytes(self, gid):
        a, b = self.loca(gid), self.loca(gid + 1)
        if b <= a:
            return b""
        g = self.tab["glyf"][0]
        return self.d[g + a:g + b]

    # ------------------------------------------------------------ hmtx
    def metric(self, gid):
        h = self.tab["hmtx"][0]
        if gid < self.nhmetrics:
            return u16(self.d, h + gid * 4), s16(self.d, h + gid * 4 + 2)
        adv = u16(self.d, h + (self.nhmetrics - 1) * 4)
        lsb = s16(self.d, h + self.nhmetrics * 4 + (gid - self.nhmetrics) * 2)
        return adv, lsb

    # ------------------------------------------------------------ cmap
    def cmap(self):
        """Zeichen -> Glyphe, aus der besten Untertabelle."""
        off = self.tab["cmap"][0]
        n = u16(self.d, off + 2)
        gewaehlt = None
        for i in range(n):
            pid, eid, sub = struct.unpack_from(">HHI", self.d, off + 4 + 8 * i)
            rang = {(3, 10): 4, (3, 1): 3, (0, 3): 3, (0, 4): 3,
                    (3, 0): 1, (1, 0): 0}.get((pid, eid), -1)
            if rang >= 0 and (gewaehlt is None or rang > gewaehlt[0]):
                gewaehlt = (rang, off + sub)
        if gewaehlt is None:
            raise SystemExit("schnitt: keine brauchbare cmap")
        return self._sub(gewaehlt[1])

    def _sub(self, o):
        fmt = u16(self.d, o)
        m = {}
        if fmt == 4:
            segx2 = u16(self.d, o + 6)
            seg = segx2 // 2
            enden = o + 14
            anfaenge = enden + segx2 + 2
            deltas = anfaenge + segx2
            bereiche = deltas + segx2
            for i in range(seg):
                e = u16(self.d, enden + i * 2)
                a = u16(self.d, anfaenge + i * 2)
                dl = u16(self.d, deltas + i * 2)
                ro = u16(self.d, bereiche + i * 2)
                if a > e:
                    continue
                for c in range(a, min(e, 0xFFFE) + 1):
                    if ro == 0:
                        g = (c + dl) & 0xFFFF
                    else:
                        p = bereiche + i * 2 + ro + (c - a) * 2
                        if p + 1 >= len(self.d):
                            continue
                        g = u16(self.d, p)
                        if g:
                            g = (g + dl) & 0xFFFF
                    if g:
                        m[c] = g
        elif fmt == 12:
            ngr = u32(self.d, o + 12)
            for i in range(ngr):
                a, e, gs = struct.unpack_from(">III", self.d, o + 16 + 12 * i)
                for c in range(a, min(e, a + 0x10000) + 1):
                    m[c] = gs + (c - a)
        elif fmt == 6:
            erst = u16(self.d, o + 6)
            anz = u16(self.d, o + 8)
            for i in range(anz):
                m[erst + i] = u16(self.d, o + 10 + i * 2)
        else:
            raise SystemExit("schnitt: cmap-Format %d wird nicht gelesen" % fmt)
        return m

    # ------------------------------------------------------------ kern
    def kern0(self):
        """Format-0-Paare aus der ersten waagerechten Untertabelle."""
        if "kern" not in self.tab:
            return {}
        o, _ = self.tab["kern"]
        if u16(self.d, o) != 0:
            return {}
        n = u16(self.d, o + 2)
        p = o + 4
        paare = {}
        for _i in range(n):
            sublen = u16(self.d, p + 2)
            deckung = u16(self.d, p + 4)
            fmt = deckung >> 8
            waagerecht = (deckung & 1) == 1
            if fmt == 0 and waagerecht:
                anz = u16(self.d, p + 6)
                for i in range(anz):
                    li, re, w = struct.unpack_from(">HHh", self.d,
                                                   p + 14 + 6 * i)
                    if w:
                        paare[(li, re)] = w
                break
            if sublen == 0:
                break
            p += sublen
        return paare


# ------------------------------------------------------- zusammenbauen

def komponenten(roh):
    """Die Glyphennummern, aus denen eine zusammengesetzte Glyphe besteht."""
    if len(roh) < 10 or s16(roh, 0) >= 0:
        return []
    aus = []
    p = 10
    while True:
        flags = u16(roh, p)
        gid = u16(roh, p + 2)
        aus.append(gid)
        p += 4
        p += 4 if (flags & 1) else 2          # ARG_1_AND_2_ARE_WORDS
        if flags & 8:                         # WE_HAVE_A_SCALE
            p += 2
        elif flags & 0x40:                    # X_AND_Y_SCALE
            p += 4
        elif flags & 0x80:                    # TWO_BY_TWO
            p += 8
        if not (flags & 0x20):                # MORE_COMPONENTS
            break
    return aus


def komponenten_neu(roh, karte):
    """Dieselbe Glyphe, aber mit umnummerierten Bestandteilen."""
    aus = bytearray(roh)
    p = 10
    while True:
        flags = u16(aus, p)
        gid = u16(aus, p + 2)
        struct.pack_into(">H", aus, p + 2, karte[gid])
        p += 4
        p += 4 if (flags & 1) else 2
        if flags & 8:
            p += 2
        elif flags & 0x40:
            p += 4
        elif flags & 0x80:
            p += 8
        if not (flags & 0x20):
            break
    return bytes(aus)


def pad4(b):
    return b + b"\x00" * ((4 - len(b) % 4) % 4)


def summe(b):
    b = pad4(b)
    s = 0
    for i in range(0, len(b), 4):
        s = (s + u32(b, i)) & 0xFFFFFFFF
    return s


def cmap4(paare):
    """Format 4, ein Segment je zusammenhaengendem Block plus 0xFFFF."""
    zeichen = sorted(paare)
    segmente = []
    i = 0
    while i < len(zeichen):
        a = zeichen[i]
        j = i
        while (j + 1 < len(zeichen) and zeichen[j + 1] == zeichen[j] + 1
               and paare[zeichen[j + 1]] == paare[zeichen[j]] + 1):
            j += 1
        segmente.append((a, zeichen[j], (paare[a] - a) & 0xFFFF))
        i = j + 1
    segmente.append((0xFFFF, 0xFFFF, 1))
    n = len(segmente)
    suchbereich = 2
    while suchbereich * 2 <= n * 2:
        suchbereich *= 2
    eintrag = 0
    v = suchbereich // 2
    while v > 1:
        eintrag += 1
        v //= 2
    kopf = struct.pack(">HHHHHHH", 4, 16 + n * 8, 0, n * 2, suchbereich,
                       eintrag, n * 2 - suchbereich)
    enden = b"".join(struct.pack(">H", s[1]) for s in segmente)
    anfaenge = b"".join(struct.pack(">H", s[0]) for s in segmente)
    deltas = b"".join(struct.pack(">H", s[2]) for s in segmente)
    bereiche = b"\x00\x00" * n
    unter = kopf + enden + b"\x00\x00" + anfaenge + deltas + bereiche
    return struct.pack(">HHHHI", 0, 1, 3, 1, 12) + unter


def kern0_bauen(paare):
    if not paare:
        return None
    liste = sorted(paare)
    n = len(liste)
    suchbereich = 6
    while suchbereich * 2 <= n * 6:
        suchbereich *= 2
    eintrag = 0
    v = suchbereich // 6
    while v > 1:
        eintrag += 1
        v //= 2
    koerper = struct.pack(">HHHH", n, suchbereich, eintrag,
                          n * 6 - suchbereich)
    for li, re in liste:
        koerper += struct.pack(">HHh", li, re, paare[(li, re)])
    unter = struct.pack(">HHH", 0, 14 + len(koerper), 0x0001) + koerper
    return struct.pack(">HH", 0, 1) + unter


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    quelle, ziel = argv[1], argv[2]
    erst = int(argv[3], 0) if len(argv) > 3 else 0x20
    letzt = int(argv[4], 0) if len(argv) > 4 else 0x7E

    v = Vorlage(quelle)
    voll = v.cmap()

    # 1. Welche Glyphen bleiben -- samt Bestandteilen zusammengesetzter.
    behalten = [0]
    zeichen = {}
    for c in range(erst, letzt + 1):
        g = voll.get(c)
        if g is None:
            continue
        zeichen[c] = g
        if g not in behalten:
            behalten.append(g)
    offen = list(behalten)
    while offen:
        g = offen.pop()
        for k in komponenten(v.glyph_bytes(g)):
            if k not in behalten:
                behalten.append(k)
                offen.append(k)
    behalten.sort()
    karte = {alt: neu for neu, alt in enumerate(behalten)}

    # 2. glyf und loca.
    glyf = bytearray()
    versatz = []
    for alt in behalten:
        versatz.append(len(glyf))
        roh = v.glyph_bytes(alt)
        if roh and s16(roh, 0) < 0:
            roh = komponenten_neu(roh, karte)
        glyf += pad4(roh)
    versatz.append(len(glyf))
    lang = versatz[-1] > 0x1FFFE
    if lang:
        loca = b"".join(struct.pack(">I", o) for o in versatz)
    else:
        loca = b"".join(struct.pack(">H", o // 2) for o in versatz)

    # 3. hmtx -- eine volle Metrik je Glyphe.  Das kostet zwei Oktette je
    #    Glyphe mehr und spart dem Kernel den Sonderfall "hinter der
    #    letzten Laufweite stehen nur noch Seitenabstaende".
    hmtx = b"".join(struct.pack(">Hh", *v.metric(alt)) for alt in behalten)

    # 4. die drei Koepfe.
    head = bytearray(v.d[v.tab["head"][0]:v.tab["head"][0] + 54])
    struct.pack_into(">h", head, 50, 1 if lang else 0)
    struct.pack_into(">I", head, 8, 0)  # checkSumAdjustment, unten gesetzt
    hhea = bytearray(v.d[v.tab["hhea"][0]:v.tab["hhea"][0] + 36])
    struct.pack_into(">H", hhea, 34, len(behalten))
    maxp = bytearray(v.d[v.tab["maxp"][0]:v.tab["maxp"][0] + 32])
    struct.pack_into(">H", maxp, 4, len(behalten))

    tabellen = {
        "cmap": cmap4({c: karte[g] for c, g in zeichen.items()}),
        "glyf": bytes(glyf),
        "head": bytes(head),
        "hhea": bytes(hhea),
        "hmtx": hmtx,
        "loca": loca,
        "maxp": bytes(maxp),
    }
    kp = {(karte[a], karte[b]): w for (a, b), w in v.kern0().items()
          if a in karte and b in karte}
    k = kern0_bauen(kp)
    if k:
        tabellen["kern"] = k

    marken = sorted(tabellen)
    n = len(marken)
    suchbereich = 16
    while suchbereich * 2 <= n * 16:
        suchbereich *= 2
    eintrag = 0
    x = suchbereich // 16
    while x > 1:
        eintrag += 1
        x //= 2
    kopf = struct.pack(">IHHHH", 0x00010000, n, suchbereich, eintrag,
                       n * 16 - suchbereich)
    pos = 12 + 16 * n
    verz = b""
    koerper = b""
    for m in marken:
        d = tabellen[m]
        verz += struct.pack(">4sIII", m.encode("latin1"), summe(d), pos,
                            len(d))
        koerper += pad4(d)
        pos += len(pad4(d))
    datei = bytearray(kopf + verz + koerper)
    pruef = (0xB1B0AFBA - summe(bytes(datei))) & 0xFFFFFFFF
    for i, m in enumerate(marken):
        if m == "head":
            hoff = u32(datei, 12 + 16 * i + 8)
            struct.pack_into(">I", datei, hoff + 8, pruef)

    open(ziel, "wb").write(bytes(datei))
    print("%s: %d Glyphen, %d Zeichen, %d Oktette (%s), upm=%d, "
          "asc=%d desc=%d gap=%d, kern=%d Paare"
          % (ziel, len(behalten), len(zeichen), len(datei),
             ", ".join(marken), v.upm, v.ascent, v.descent, v.gap, len(kp)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
