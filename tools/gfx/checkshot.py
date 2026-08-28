#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/gfx/checkshot.py -- ein Bildschirmfoto MASCHINELL pruefen.

Ein Test, der nur sagt "der Kernel ist nicht abgestuerzt", beweist ueber
einen Bildschirm gar nichts.  Deshalb macht `tools/gfx/run.sh` echte
Bildschirmfotos ueber den QEMU-Monitor (`screendump`, das Ergebnis ist ein
PPM in P6), und dieses Programm rechnet sie nach:

  groesse    Breite und Hoehe -- der Beweis, dass der Bildmodus wirklich
             gesetzt wurde.  Ohne Grafik zeigt dieselbe Maschine 720x400
             (VGA-Textmodus), mit Grafik 800x600.
  punkt      die Farbe an einer Stelle.
  flaeche    wie viele Bildpunkte eines Rechtecks NICHT die erwartete
             Farbe haben.
  nichtleer  wie viele Bildpunkte eines Rechtecks nicht schwarz sind.
  text       eine Textzeile BILDPUNKTGENAU gegen den Zeichensatz -- nicht
             "da ist irgendwas hell", sondern: an jeder der 128 Stellen
             jeder Glyphe steht Vorder- oder Hintergrundfarbe, so wie die
             Bitmaske es sagt.
  finde      wie `konsole`, aber fuer EINE gesuchte Zeile -- damit im
             Fehlerfall dasteht, WELCHE Zeile nicht stimmt.
  konsole    das GANZE Bild gegen den seriellen Mitschnitt.  Der
             Mitschnitt wird durch dieselbe Zustandsmaschine geschickt,
             die `fb.putc` ist (Umbruch am Zeilenende, Rollen, Tabulator,
             Ruecktaste), das Ergebnis mit dem Zeichensatz gemalt und
             Bildpunkt fuer Bildpunkt verglichen.  DAS ist die Zusage
             "beide Ausgaben zeigen dasselbe".
  font       der Zeichensatz in kernel/font.fi gegen die Rust-Vorlage, aus
             der er portiert wurde.
  ttext      eine Zeile ECHTER Schrift (TrueType, kantengeglaettet) --
             gegen `tools/ttf/raster.py`, die zweite Fassung des
             Rasterers aus `kernel/ttf.fi`.
  tgrid      dasselbe fuer ein ZEICHENRASTER (ein Terminalfenster).
  glatt      ist es wirklich eine Kantenglaettung? Zaehlt die
             Zwischenstufen -- eine Rasterung ohne Glaettung hat keine.
  rechteck   ein Fensterrahmen: die vier Kanten in der Farbe, einen
             Bildpunkt daneben nicht.
  lesen      das Bild ZURUECK IN TEXT: jede Zelle wird gegen alle 95
             Glyphen gehalten und der Buchstabe ausgegeben, der dort
             wirklich steht.  Damit sieht man, was der Bildschirm zeigt,
             statt nur zu erfahren, wie viele Bildpunkte falsch sind.

RUNDE K7B: `text`, `konsole` und `finde` melden im Fehlerfall nicht mehr
nur eine Zahl, sondern JEDE abweichende Zelle mit Soll und Ist -- und das
Ist wird gegen den Zeichensatz erkannt, nicht geraten.  Genau das hat den
Fehler dieser Runde gefunden: auf dem Schirm standen nur noch '7',
'01234' und ':', also ausschliesslich Zeichen unter 0x40, waehrend jeder
Buchstabe leer blieb.  Aus "410 von 3200 Bildpunkten falsch" liest das
niemand heraus; aus "soll 'O', ist ' '" liest es jeder.

Der Zeichensatz wird IMMER aus `kernel/font.fi` gelesen, nie aus einer
Kopie: geprueft werden soll der, der im Kernel steht.

Jeder Unterbefehl schreibt EINE Zeile und gibt 0 zurueck, wenn alles
stimmt, sonst 1.
"""
import re
import sys


# ------------------------------------------------------------------ PPM

def ppm_lesen(pfad):
    """P6 -- das schreibt QEMUs `screendump`."""
    roh = open(pfad, "rb").read()
    if not roh.startswith(b"P6"):
        raise ValueError("kein P6-PPM: %s" % pfad)
    felder = []
    i = 2
    while len(felder) < 3:
        while i < len(roh) and roh[i:i + 1].isspace():
            i += 1
        if roh[i:i + 1] == b"#":
            while i < len(roh) and roh[i] != 0x0A:
                i += 1
            continue
        j = i
        while j < len(roh) and not roh[j:j + 1].isspace():
            j += 1
        felder.append(int(roh[i:j]))
        i = j
    i += 1  # das eine Trennzeichen hinter dem Hoechstwert
    b, h, _ = felder
    return b, h, roh[i:i + b * h * 3]


class Bild:
    def __init__(self, pfad):
        self.b, self.h, self.d = ppm_lesen(pfad)

    def punkt(self, x, y):
        if x < 0 or y < 0 or x >= self.b or y >= self.h:
            return None
        o = (y * self.b + x) * 3
        return (self.d[o], self.d[o + 1], self.d[o + 2])


# ----------------------------------------------------------- Zeichensatz

ERSTES = 0x20
LETZTES = 0x7E
HOCH = 16
BREIT = 8


def font_aus_firn(pfad):
    """Die zehn b"..."-Stuecke aus kernel/font.fi, in ihrer Reihenfolge."""
    quelle = open(pfad, "r", encoding="utf-8").read()
    stuecke = re.findall(r'var b: \[u8; \d+\] = b"((?:\\x[0-9a-fA-F]{2})+)"',
                         quelle)
    daten = bytearray()
    for s in stuecke:
        daten += bytes(int(v, 16)
                       for v in re.findall(r"\\x([0-9a-fA-F]{2})", s))
    return bytes(daten)


def font_aus_rust(pfad):
    """Die Glyphentabelle aus OrientOS' kernel/src/drivers/font.rs."""
    quelle = open(pfad, "r", encoding="utf-8").read()
    zeilen = re.findall(r"\[((?:0x[0-9a-fA-F]{2},\s*){15}0x[0-9a-fA-F]{2})\]",
                        quelle)
    daten = bytearray()
    for z in zeilen:
        daten += bytes(int(v, 16)
                       for v in re.findall(r"0x([0-9a-fA-F]{2})", z))
    return bytes(daten)


def glyphe(font, zeichen):
    c = zeichen
    if c < ERSTES or c > LETZTES:
        c = 0x3F  # '?', genau wie `font.row`
    i = (c - ERSTES) * HOCH
    return font[i:i + HOCH]


# ---------------------------------------------------- die Konsole in Klein
#
# Eine Nachbildung von `fb.putc`, Zeichen fuer Zeichen dieselben
# Entscheidungen.  Ergebnis ist ein Raster aus Zellen; eine Zelle ist
# entweder leer (nie beschrieben, also Hintergrund) oder ein Zeichen.

class Konsole:
    def __init__(self, spalten, zeilen):
        self.sp = spalten
        self.ze = zeilen
        self.gitter = [[None] * spalten for _ in range(zeilen)]
        self.x = 0
        self.y = 0

    def rollen(self):
        self.gitter.pop(0)
        self.gitter.append([None] * self.sp)

    def umbruch(self):
        self.x = 0
        self.y += 1
        if self.y >= self.ze:
            self.rollen()
            self.y = self.ze - 1

    def weiter(self):
        self.x += 1
        if self.x >= self.sp:
            self.umbruch()

    def zeichen(self, c):
        self.gitter[self.y][self.x] = c
        self.weiter()

    def put(self, c):
        if c == 10:
            self.umbruch()
            return
        if c == 13:
            self.x = 0
            return
        if c == 8:
            if self.x > 0:
                self.x -= 1
                self.gitter[self.y][self.x] = 32
            return
        if c == 9:
            for _ in range(8 - (self.x & 7)):
                self.zeichen(32)
            return
        self.zeichen(c)

    def text(self, oktette):
        for c in oktette:
            self.put(c)


# ----------------------------------------------------------- Unterbefehle

VG = (200, 208, 216)   # 0xC8 0xD0 0xD8 -- die Vordergrundfarbe von `fb.init`
HG = (0, 0, 0)


def farbe_von(args, i):
    return (int(args[i]), int(args[i + 1]), int(args[i + 2]))


def zeile_pruefen(bild, font, zeile, spalte, text, vg, hg):
    falsch = 0
    gesamt = 0
    for k, zeichen in enumerate(text):
        g = glyphe(font, zeichen)
        for r in range(HOCH):
            bits = g[r]
            for c in range(BREIT):
                x = (spalte + k) * BREIT + c
                y = zeile * HOCH + r
                soll = vg if (bits >> (7 - c)) & 1 else hg
                gesamt += 1
                if bild.punkt(x, y) != soll:
                    falsch += 1
    return gesamt, falsch


def erkennen(bild, font, zy, zx, vg=None, hg=None):
    """Welches Zeichen steht WIRKLICH in dieser Zelle?

    Die Zelle wird gegen alle 95 Glyphen des Zeichensatzes gehalten; der
    mit den wenigsten Abweichungen gewinnt.  Zurueck kommt (Zeichen,
    Abweichungen) -- ist die zweite Zahl 0, steht dort genau diese Glyphe,
    sonst ist es das aehnlichste und die Zelle ist etwas anderes.
    """
    vg = VG if vg is None else vg
    hg = HG if hg is None else hg
    bestes = None
    bestf = 1 << 30
    for c in range(ERSTES, LETZTES + 1):
        _, f = zeile_pruefen(bild, font, zy, zx, bytes([c]), vg, hg)
        if f < bestf:
            bestf = f
            bestes = c
            if f == 0:
                break
    return bestes, bestf


def sichtbar(c):
    if c is None:
        return "?"
    if c == 0x20:
        return "_"  # ein Leerzeichen soll man im Bericht sehen
    return chr(c)


HOECHSTENS = 16  # so viele abweichende Zellen werden einzeln genannt


def bericht(bild, font, faelle, vg=None, hg=None):
    """Die abweichenden Zellen EINZELN nennen, mit Soll und erkanntem Ist.

    `faelle` ist eine Liste (zeile, spalte, sollzeichen).  Ausgegeben wird
    nur, was wirklich abweicht.
    """
    schlecht = []
    for zy, zx, soll in faelle:
        _, f = zeile_pruefen(bild, font, zy, zx, bytes([soll]), vg or VG,
                             hg or HG)
        if f:
            ist, iff = erkennen(bild, font, zy, zx, vg, hg)
            schlecht.append((zy, zx, soll, ist, iff, f))
    if not schlecht:
        return
    print("  %d abweichende Zellen:" % len(schlecht))
    for zy, zx, soll, ist, iff, f in schlecht[:HOECHSTENS]:
        wie = "'%s'" % sichtbar(ist) if iff == 0 else \
              "etwas anderes (am naechsten '%s', %d Bildpunkte daneben)" \
              % (sichtbar(ist), iff)
        print("    Zeile %d Spalte %d: soll '%s' (0x%02X), ist %s"
              " -- %d Bildpunkte falsch"
              % (zy, zx, sichtbar(soll), soll, wie, f))
    if len(schlecht) > HOECHSTENS:
        print("    ... und %d weitere" % (len(schlecht) - HOECHSTENS))


def cmd_groesse(a):
    bild = Bild(a[0])
    print("%d %d" % (bild.b, bild.h))
    if len(a) >= 3 and (bild.b, bild.h) != (int(a[1]), int(a[2])):
        return 1
    return 0


def cmd_punkt(a):
    bild = Bild(a[0])
    p = bild.punkt(int(a[1]), int(a[2]))
    if p is None:
        print("ausserhalb des Bildes")
        return 1
    print("%d %d %d" % p)
    if len(a) >= 6 and p != farbe_von(a, 3):
        return 1
    return 0


def cmd_flaeche(a):
    bild = Bild(a[0])
    x, y, b, h = (int(v) for v in a[1:5])
    soll = farbe_von(a, 5)
    falsch = 0
    for yy in range(y, y + h):
        for xx in range(x, x + b):
            if bild.punkt(xx, yy) != soll:
                falsch += 1
    print("%d von %d Bildpunkten falsch" % (falsch, b * h))
    return 0 if falsch == 0 else 1


def cmd_nichtleer(a):
    bild = Bild(a[0])
    x, y, b, h = (int(v) for v in a[1:5])
    n = 0
    for yy in range(y, y + h):
        for xx in range(x, x + b):
            p = bild.punkt(xx, yy)
            if p is not None and p != HG:
                n += 1
    print("%d" % n)
    return 0 if n >= (int(a[5]) if len(a) >= 6 else 0) else 1


def cmd_text(a):
    # text <ppm> <font.fi> <zeile> <spalte> <text> [vgR vgG vgB hgR hgG hgB]
    bild = Bild(a[0])
    font = font_aus_firn(a[1])
    text = a[4].encode("ascii", "replace")
    vg = farbe_von(a, 5) if len(a) >= 8 else VG
    hg = farbe_von(a, 8) if len(a) >= 11 else HG
    zeile, spalte = int(a[2]), int(a[3])
    gesamt, falsch = zeile_pruefen(bild, font, zeile, spalte, text, vg, hg)
    print("%d Bildpunkte geprueft, %d falsch" % (gesamt, falsch))
    if falsch:
        bericht(bild, font,
                [(zeile, spalte + k, c) for k, c in enumerate(text)], vg, hg)
    return 0 if falsch == 0 else 1


def cmd_konsole(a):
    # konsole <ppm> <font.fi> <seriell> <startmarke> <endmarke> [minzellen]
    bild = Bild(a[0])
    font = font_aus_firn(a[1])
    roh = open(a[2], "rb").read()
    minzellen = int(a[5]) if len(a) >= 6 else 500

    i = roh.find(a[3].encode())
    if i < 0:
        print("Startmarke '%s' fehlt im Mitschnitt" % a[3])
        return 1
    j = roh.find(a[4].encode(), i)
    if j < 0:
        print("Endmarke '%s' fehlt im Mitschnitt" % a[4])
        return 1
    j = roh.find(b"\n", j)
    j = len(roh) if j < 0 else j + 1

    k = Konsole(bild.b // BREIT, bild.h // HOCH)
    k.text(roh[i:j])

    falsch = 0
    gesamt = 0
    zellen = 0
    faelle = []
    for zy in range(k.ze):
        for zx in range(k.sp):
            c = k.gitter[zy][zx]
            if c is None:
                continue
            zellen += 1
            faelle.append((zy, zx, c))
            g, f = zeile_pruefen(bild, font, zy, zx, bytes([c]), VG, HG)
            gesamt += g
            falsch += f
    print("%d Zellen, %d Bildpunkte, %d falsch" % (zellen, gesamt, falsch))
    if zellen < minzellen:
        print("  zu wenige Zellen -- der Mitschnitt kam nicht auf den Schirm")
        return 1
    if falsch:
        bericht(bild, font, faelle)
    return 0 if falsch == 0 else 1


def cmd_finde(a):
    """finde <ppm> <font.fi> <seriell> <start> <ende> <text>

    Wie `konsole`, aber fuer EINE Zeile: der Mitschnitt wird durch
    dieselbe Zustandsmaschine geschickt, in dem Ergebnis die Zeile mit dem
    gesuchten Text gesucht -- und GENAU DIESE Zeile dann bildpunktgenau
    gegen das Foto gehalten.  So steht im Fehlerfall da, WELCHE Zeile
    nicht stimmt, statt nur "irgendwo im Bild".
    """
    bild = Bild(a[0])
    font = font_aus_firn(a[1])
    roh = open(a[2], "rb").read()
    gesucht = a[5].encode()

    i = roh.find(a[3].encode())
    if i < 0:
        print("Startmarke '%s' fehlt im Mitschnitt" % a[3])
        return 1
    j = roh.find(a[4].encode(), i)
    if j < 0:
        print("Endmarke '%s' fehlt im Mitschnitt" % a[4])
        return 1
    j = roh.find(b"\n", j)
    j = len(roh) if j < 0 else j + 1

    k = Konsole(bild.b // BREIT, bild.h // HOCH)
    k.text(roh[i:j])

    for zy in range(k.ze):
        zeile = bytes((c if c is not None else 32) for c in k.gitter[zy])
        p = zeile.find(gesucht)
        if p >= 0:
            g, f = zeile_pruefen(bild, font, zy, p, gesucht, VG, HG)
            print("Zeile %d, Spalte %d: %d Bildpunkte, %d falsch"
                  % (zy, p, g, f))
            if f:
                bericht(bild, font,
                        [(zy, p + i, c) for i, c in enumerate(gesucht)])
            return 0 if f == 0 else 1
    print("'%s' steht nicht auf dem nachgebildeten Bildschirm" % a[5])
    return 1


def cmd_font(a):
    # font <font.fi> [font.rs]
    fi = font_aus_firn(a[0])
    soll = (LETZTES - ERSTES + 1) * HOCH
    if len(fi) != soll:
        print("kernel/font.fi hat %d Oktette, erwartet %d" % (len(fi), soll))
        return 1
    if len(a) < 2:
        print("%d Oktette, 95 Glyphen (Vorlage nicht vorhanden)" % len(fi))
        return 0
    rs = font_aus_rust(a[1])
    if len(rs) != len(fi):
        print("Vorlage %d Oktette, Portierung %d" % (len(rs), len(fi)))
        return 1
    anders = sum(1 for x, y in zip(fi, rs) if x != y)
    print("%d Oktette gegen die Rust-Vorlage, %d verschieden"
          % (len(fi), anders))
    return 0 if anders == 0 else 1


def cmd_lesen(a):
    """lesen <ppm> <font.fi> [zeile [zeilen]]

    Das Bild zurueck in Text.  Jede Zelle wird gegen alle Glyphen
    gehalten: passt genau eine, steht sie da; ist die Zelle ganz schwarz,
    steht ein Leerzeichen; ist etwas anderes darin (Farbfelder, Linien),
    steht '#'; passt keine Glyphe, steht '~'.

    Das ist das Werkzeug, mit dem man ANSIEHT, was auf dem Schirm steht,
    statt Bildpunkte zu zaehlen.
    """
    bild = Bild(a[0])
    font = font_aus_firn(a[1])
    von = int(a[2]) if len(a) >= 3 else 0
    anzahl = int(a[3]) if len(a) >= 4 else bild.h // HOCH - von
    muster = {}
    for c in range(ERSTES, LETZTES + 1):
        muster.setdefault(bytes(glyphe(font, c)), c)
    print("%dx%d, %d Spalten, %d Zeilen"
          % (bild.b, bild.h, bild.b // BREIT, bild.h // HOCH))
    for zy in range(von, min(von + anzahl, bild.h // HOCH)):
        zeile = []
        for zx in range(bild.b // BREIT):
            bits = []
            fremd = False
            for r in range(HOCH):
                v = 0
                for c in range(BREIT):
                    p = bild.punkt(zx * BREIT + c, zy * HOCH + r)
                    if p == VG:
                        v |= 1 << (7 - c)
                    elif p != HG:
                        fremd = True
                bits.append(v)
            if fremd:
                zeile.append("#")
            elif bytes(bits) in muster:
                zeile.append(chr(muster[bytes(bits)]))
            elif any(bits):
                zeile.append("~")
            else:
                zeile.append(" ")
        print("%3d |%s|" % (zy, "".join(zeile)))
    return 0



# ---------------------------------------------- RUNDE K10: echte Schriften
#
# Der 8x16-Zeichensatz aus Runde K7 ist eine Bitmaske: ein Bildpunkt ist
# an oder aus, und `text` oben vergleicht ihn Bit fuer Bit.  Bei einer
# KANTENGEGLAETTETEN Schrift gibt es das nicht mehr -- es gibt
# Zwischenstufen, und die haengen an einem Algorithmus.  Also wird gegen
# den Algorithmus geprueft: `tools/ttf/raster.py` ist die zweite Fassung
# des Rasterers aus `kernel/ttf.fi`, und beide muessen dasselbe liefern.
#
# UND DIE LEHRE AUS RUNDE K7B STEHT HIER IM MITTELPUNKT.  Dort schien
# Text zu 87 Prozent zu stimmen, waehrend in Wahrheit JEDER BUCHSTABE
# fehlte -- die 87 Prozent waren schwarzer Hintergrund.  Deshalb zaehlt
# dieser Pruefer nicht Bildpunkte gegen die Flaeche, sondern:
#
#   * je Zeichen die GESETZTEN Bildpunkte (Deckkraft > 0) der Vorlage,
#   * wie viele davon im Bild wirklich stehen,
#   * und er FAELLT, wenn ein Zeichen mit Umriss im Bild keine Tinte hat.
#
# Ein leeres Rechteck geht hier nicht durch, egal wie gross es ist.

def _raster_laden():
    import os
    hier = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, os.path.join(hier, "..", "ttf"))
    import raster
    return raster


def mische(alt, neu, a):
    """Dieselbe Zeile wie `fb.blend`, `wm.blend` und `wlibc.blend`.

    RUNDE PAINT: hier stand `// 255` -- abschneiden.  Der Kern rundet
    seit dieser Runde kaufmaennisch, weil abschneiden gegen die exakte
    Rechnung auf 8 164 890 von 16 777 216 Tripeln (a, src, dst) um eins
    danebenliegt, also auf 48.67 Prozent von ihnen.  `(num + 127) // 255`
    ist auf allen 16.7 Millionen exakt und gleich dem, was der Kern mit
    `(t + (t >> 8)) >> 8` rechnet -- nachgewiesen in
    tools/paint/blendcheck.py, das genau diese Gleichheit prueft.
    """
    if a == 0:
        return alt
    if a >= 255:
        return neu
    ia = 255 - a
    return tuple((alt[k] * ia + neu[k] * a + 127) // 255 for k in range(3))


def _pruefe_glyphen(bild, schrift, stellen, grund_y, vg, hg, toleranz,
                    breite=0):
    """stellen: [(zeichen, x_in_bildpunkten, y_grundlinie)] -- prueft jede.

    Gibt (zeichen_geprueft, tinte_geprueft, tinte_falsch, leere_zeichen,
          bericht)."""
    zeichen = 0
    tinte = 0
    falsch = 0
    leer = []
    schlecht = []
    for (c, gx, gy) in stellen:
        g = schrift.glyphe(c)
        if g.w == 0 or g.h == 0:
            continue                      # Leerzeichen haben keinen Umriss
        # Im Zeichenraster wird auf die ZELLE beschnitten -- genau so,
        # wie `wm.draw_glyph_clip` es tut.
        lo = gx if breite else None
        hi = gx + breite if breite else None
        zeichen += 1
        gesetzt = 0
        getroffen = 0
        schlimm = 0
        for r in range(g.h):
            for k in range(g.w):
                a = g.punkt(k, r)
                if a == 0:
                    continue
                px = gx + g.links + k
                py = gy - g.oben + r
                if lo is not None and (px < lo or px >= hi):
                    continue
                gesetzt += 1
                soll = mische(hg, vg, a)
                ist = bild.punkt(px, py)
                if ist is None:
                    schlimm += 1
                    continue
                if max(abs(ist[j] - soll[j]) for j in range(3)) <= toleranz:
                    getroffen += 1
                else:
                    schlimm += 1
        tinte += gesetzt
        falsch += schlimm
        # DIE ZUSAGE GEGEN DEN SCHWARZEN HINTERGRUND: hat die Stelle im
        # BILD ueberhaupt Tinte?  Ein Zeichen, dessen Vorlage sechzig
        # gesetzte Bildpunkte hat und im Bild keinen einzigen vom
        # Hintergrund verschiedenen, ist nicht "zu 87 Prozent richtig",
        # sondern gar nicht da.
        ink_im_bild = 0
        for r in range(g.h):
            for k in range(g.w):
                if g.punkt(k, r) == 0:
                    continue
                if lo is not None:
                    if gx + g.links + k < lo or gx + g.links + k >= hi:
                        continue
                ist = bild.punkt(gx + g.links + k, gy - g.oben + r)
                if ist is not None and ist != hg:
                    ink_im_bild += 1
        if gesetzt > 0 and ink_im_bild == 0:
            leer.append(sichtbar(c))
        if schlimm and len(schlecht) < 8:
            schlecht.append("'%s' bei x=%d: %d von %d Tintenpunkten falsch"
                            % (sichtbar(c), gx, schlimm, gesetzt))
    return zeichen, tinte, falsch, leer, schlecht


def cmd_tkette(a):
    """tkette <ppm> <ttf> <px> <x> <grundlinie> <vg r g b> <hg r g b> <text>

    WIE `ttext`, ABER MIT DER RICHTIGEN ERWARTUNG AN UEBERLAPPENDEN
    UMRISSEN -- und das ist keine Aufweichung, sondern das Gegenteil.

    `ttext` rechnet je Zeichen `mische(hintergrund, vordergrund, deckung)`
    und setzt damit voraus, dass unter jedem Bildpunkt eines Buchstabens
    der reine Hintergrund liegt.  Das stimmt fast immer und bei eng
    unterschnittenen Paaren NICHT: die Umrisse von 'a' und 'r' in
    "Start" ueberschneiden sich um einen Bildpunkt, und dort mischt
    JEDER Rasterer -- Osum, FreeType, Cairo -- den zweiten Buchstaben
    auf den bereits gemischten ersten.  Gemessen am 27.08.2026: 4 von
    200 Tintenpunkten in "Start", und `ttext` nannte sie falsch, obwohl
    das Bild richtig war.

    Diese Fassung baut deshalb ERST die ganze Zeile so auf, wie sie
    aufgebaut werden MUSS -- Buchstabe fuer Buchstabe auf das Ergebnis
    des vorigen --, und vergleicht DANN je Zeichen.  Die Toleranz bleibt
    null, die Zusage "jedes Zeichen hat Tinte" bleibt, und der Vergleich
    wird strenger statt weicher: er prueft jetzt auch die Reihenfolge
    des Mischens."""
    raster = _raster_laden()
    bild = Bild(a[0])
    schrift = raster.Schrift(a[1], int(a[2]))
    x, y = int(a[3]), int(a[4])
    vg = (int(a[5]), int(a[6]), int(a[7]))
    hg = (int(a[8]), int(a[9]), int(a[10]))
    text = a[11]
    tol = int(a[12]) if len(a) > 12 else 0
    stellen = [(c, x + (dx >> 6), y) for (c, dx) in schrift.stellen(text)]

    # 1. Die Zeile aufbauen, so wie sie gemalt wird: ein Woerterbuch
    #    (x, y) -> Farbe, das mit dem Hintergrund anfaengt.
    soll = {}
    for (c, gx, gy) in stellen:
        g = schrift.glyphe(c)
        if g.w == 0 or g.h == 0:
            continue
        for r in range(g.h):
            for k in range(g.w):
                d = g.punkt(k, r)
                if d == 0:
                    continue
                px = gx + g.links + k
                py = gy - g.oben + r
                soll[(px, py)] = mische(soll.get((px, py), hg), vg, d)

    # 2. Je Zeichen vergleichen -- und je Zeichen die Tinte im Bild
    #    zaehlen, genau wie `ttext`.
    zeichen = 0
    tinte = 0
    falsch = 0
    leer = []
    schlecht = []
    for (c, gx, gy) in stellen:
        g = schrift.glyphe(c)
        if g.w == 0 or g.h == 0:
            continue
        zeichen += 1
        gesetzt = 0
        schlimm = 0
        ink = 0
        for r in range(g.h):
            for k in range(g.w):
                if g.punkt(k, r) == 0:
                    continue
                px = gx + g.links + k
                py = gy - g.oben + r
                gesetzt += 1
                ist = bild.punkt(px, py)
                if ist is None:
                    schlimm += 1
                    continue
                if ist != hg:
                    ink += 1
                w = soll[(px, py)]
                if max(abs(ist[j] - w[j]) for j in range(3)) > tol:
                    schlimm += 1
        tinte += gesetzt
        falsch += schlimm
        if gesetzt > 0 and ink == 0:
            leer.append(sichtbar(c))
        if schlimm and len(schlecht) < 8:
            schlecht.append("'%s' bei x=%d: %d von %d Tintenpunkten falsch"
                            % (sichtbar(c), gx, schlimm, gesetzt))
    print("%d Zeichen, %d Tintenpunkte geprueft, %d falsch"
          % (zeichen, tinte, falsch), end="")
    if leer:
        print(" -- LEER: %s" % " ".join(leer))
        return 1
    if falsch:
        print()
        for z in schlecht:
            print("    " + z)
        return 1
    print("")
    return 0


def cmd_ttext(a):
    """ttext <ppm> <ttf> <px> <x> <grundlinie> <vg r g b> <hg r g b> <text>

    Eine Zeile freien Textes -- Laufweite und Unterschneidung aus der
    Schrift, so wie der Fensterserver sie setzt."""
    raster = _raster_laden()
    bild = Bild(a[0])
    schrift = raster.Schrift(a[1], int(a[2]))
    x, y = int(a[3]), int(a[4])
    vg = (int(a[5]), int(a[6]), int(a[7]))
    hg = (int(a[8]), int(a[9]), int(a[10]))
    text = a[11]
    tol = int(a[12]) if len(a) > 12 else 0
    stellen = [(c, x + (dx >> 6), y) for (c, dx) in schrift.stellen(text)]
    n, tinte, falsch, leer, schlecht = _pruefe_glyphen(
        bild, schrift, stellen, y, vg, hg, tol)
    print("%d Zeichen, %d Tintenpunkte geprueft, %d falsch"
          % (n, tinte, falsch), end="")
    if leer:
        print(" -- LEER: %s" % " ".join(leer))
        return 1
    if falsch:
        print()
        for z in schlecht:
            print("    " + z)
        return 1
    print("")
    return 0


def cmd_tgrid(a):
    """tgrid <ppm> <ttf> <px> <x0> <y0> <zellw> <zellh> <zeile> <spalte>
             <vg r g b> <hg r g b> <text>

    Ein Zeichenraster -- so, wie ein Terminalfenster es setzt: Spalte c
    beginnt bei x0 + c * zellw, die Grundlinie von Zeile r liegt bei
    y0 + r * zellh + Aufsteiger."""
    raster = _raster_laden()
    bild = Bild(a[0])
    schrift = raster.Schrift(a[1], int(a[2]))
    x0, y0 = int(a[3]), int(a[4])
    zw, zh = int(a[5]), int(a[6])
    zeile, spalte = int(a[7]), int(a[8])
    vg = (int(a[9]), int(a[10]), int(a[11]))
    hg = (int(a[12]), int(a[13]), int(a[14]))
    text = a[15]
    tol = int(a[16]) if len(a) > 16 else 0
    grund = y0 + zeile * zh + schrift.aufsteiger()
    stellen = [(ord(ch), x0 + (spalte + i) * zw, grund)
               for i, ch in enumerate(text)]
    n, tinte, falsch, leer, schlecht = _pruefe_glyphen(
        bild, schrift, stellen, grund, vg, hg, tol, zw)
    print("Zeile %d ab Spalte %d: %d Zeichen, %d Tintenpunkte, %d falsch"
          % (zeile, spalte, n, tinte, falsch), end="")
    if leer:
        print(" -- LEER: %s" % " ".join(leer))
        return 1
    if falsch:
        print()
        for z in schlecht:
            print("    " + z)
        return 1
    print("")
    return 0


def cmd_glatt(a):
    """glatt <ppm> <x> <y> <w> <h> <vg r g b> <hg r g b> [mindestens]

    IST ES WIRKLICH EINE KANTENGLAETTUNG?  Zaehlt die Bildpunkte des
    Rechtecks, die WEDER Vorder- NOCH Hintergrundfarbe haben, also
    Zwischenstufen sind.  Eine Rasterung ohne Glaettung hat davon keinen
    einzigen -- und wuerde durch jede Zusage gehen, die nur "da steht
    Text" prueft."""
    bild = Bild(a[0])
    x, y, w, h = int(a[1]), int(a[2]), int(a[3]), int(a[4])
    vg = (int(a[5]), int(a[6]), int(a[7]))
    hg = (int(a[8]), int(a[9]), int(a[10]))
    mind = int(a[11]) if len(a) > 11 else 1
    zwischen = 0
    ganz = 0
    for py in range(y, y + h):
        for px in range(x, x + w):
            p = bild.punkt(px, py)
            if p is None:
                continue
            ganz += 1
            if p != vg and p != hg:
                zwischen += 1
    print("%d von %d Bildpunkten sind Zwischenstufen (mindestens %d)"
          % (zwischen, ganz, mind))
    return 0 if zwischen >= mind else 1


def cmd_rechteck(a):
    """rechteck <ppm> <x> <y> <w> <h> <r g b>

    Ein Rahmen: die vier Kanten des Rechtecks haben die Farbe, und einen
    Bildpunkt AUSSERHALB hat sie nicht.  Damit laesst sich nachrechnen,
    dass ein Fenster wirklich an der Stelle und in der Groesse liegt, an
    der der Server es fuehrt."""
    bild = Bild(a[0])
    x, y, w, h = int(a[1]), int(a[2]), int(a[3]), int(a[4])
    farbe = (int(a[5]), int(a[6]), int(a[7]))
    falsch = 0
    ganz = 0
    for px in range(x, x + w):
        for py in (y, y + h - 1):
            ganz += 1
            if bild.punkt(px, py) != farbe:
                falsch += 1
    for py in range(y, y + h):
        for px in (x, x + w - 1):
            ganz += 1
            if bild.punkt(px, py) != farbe:
                falsch += 1
    aussen = 0
    for px in range(x - 1, x + w + 1):
        for py in (y - 1, y + h):
            if bild.punkt(px, py) == farbe:
                aussen += 1
    print("Rahmen %dx%d bei (%d,%d): %d von %d Kantenpunkten falsch, "
          "%d Treffer eine Reihe daneben" % (w, h, x, y, falsch, ganz, aussen))
    return 0 if falsch == 0 and aussen == 0 else 1



BEFEHLE = {
    "groesse": cmd_groesse,
    "punkt": cmd_punkt,
    "flaeche": cmd_flaeche,
    "nichtleer": cmd_nichtleer,
    "text": cmd_text,
    "konsole": cmd_konsole,
    "finde": cmd_finde,
    "font": cmd_font,
    "lesen": cmd_lesen,
    "ttext": cmd_ttext,
    "tkette": cmd_tkette,
    "tgrid": cmd_tgrid,
    "glatt": cmd_glatt,
    "rechteck": cmd_rechteck,
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in BEFEHLE:
        print(__doc__)
        return 2
    try:
        return BEFEHLE[sys.argv[1]](sys.argv[2:])
    except Exception as e:  # ein Fehler hier ist ein FEHLGESCHLAGENER Test
        print("FEHLER: %s" % e)
        return 1


if __name__ == "__main__":
    sys.exit(main())
