#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/alltag/bildref.py -- DAS BILD, VON EINEM FREMDEN DECODER GELESEN.

    bildref.py <datei>              die Zahlen des Wirts
    bildref.py pruefen <serial.txt> <datei> [<datei> ...]

Der Bildbetrachter im Gast sagt mit `-i` Art, Groesse, die Summe jedes
Farbkanals ueber alle Bildpunkte und fuenf einzelne Bildpunkte. Dieses
Skript sagt dasselbe -- gerechnet mit Pillow, also mit libpng und
libjpeg und nicht noch einmal mit dem Decoder, der geprueft werden soll.

DIE SCHRANKE IST NICHT FUER ALLE GLEICH, und das hat einen Grund:

  PNG und BMP sind VERLUSTFREI und exakt umkehrbar. Da muss jede Zahl
  auf den Punkt stimmen -- Abweichung 0.

  JPEG ist eine Naeherung, und zwei richtige Decoder kommen zu leicht
  verschiedenen Zahlen: die Umkehrtransformation ist eine
  Fliesskommarechnung, und T.81 schreibt sie nicht bis aufs letzte Bit
  vor (der Nachweis dafuer ist T.83 mit einer erlaubten Abweichung).

  UND EIN ZWEITER UNTERSCHIED, der groesser ist als der erste und hier
  offen dasteht: bei 4:2:0 und 4:2:2 liegt nur jeder zweite Farbwert
  vor. libjpeg rechnet die fehlenden mit einem Dreiecksfilter aus
  ("fancy upsampling"), kernel/user/jpeg.fi nimmt den naechsten
  Nachbarn. An einer harten Farbkante sind das bis zu siebzig Stufen
  Unterschied in EINEM Bildpunkt -- bei beiden zu Recht.

  Also wird unterschieden:
    4:4:4  jeder Bildpunkt auf 3 Stufen genau (das misst Huffman,
           Entquantisierung, IDCT und die Farbumrechnung).
    4:2:0  die Summen je Kanal, hoechstens 1 Stufe je Bildpunkt
           Abstand im Mittel -- ein Bildpunktvergleich waere hier
           kein Fehlernachweis, sondern ein Nachweis der
           Filterwahl.
"""
import re
import sys

from PIL import Image


def zahlen(pfad):
    im = Image.open(pfad)
    art = im.format.lower()
    voll = True
    if art == "jpeg":
        for _id, hs, vs, _q in im.layer:
            if hs != 1 or vs != 1:
                voll = False
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    sr = sg = sb = 0
    for y in range(h):
        for x in range(w):
            r, g, b, _a = px[x, y]
            sr += r
            sg += g
            sb += b
    punkte = []
    for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1),
                 (w // 2, h // 2)):
        r, g, b, _a = px[x, y]
        punkte.append((x, y, (r << 16) | (g << 8) | b))
    if art == "jpeg":
        art = "jpeg"
    return dict(art=art, w=w, h=h, sr=sr, sg=sg, sb=sb, punkte=punkte,
                voll=voll)


def gast(text, name):
    """Die drei Zeilen, die `viewer -i` fuer EINE Datei gedruckt hat."""
    marke = "viewer: datei " + name
    at = text.find(marke)
    if at < 0:
        return None
    teil = text[at:at + 1200]
    m = re.search(r"viewer: art=(\w+) w=(\d+) h=(\d+)", teil)
    if not m:
        return None
    s = re.search(r"viewer: summe (\d+) w=(\d+) h=(\d+)", teil)
    p = re.findall(r" (\d+),(\d+)=([0-9a-f]{6})", teil)
    if not s or len(p) < 5:
        return None
    return dict(art=m.group(1), w=int(m.group(2)), h=int(m.group(3)),
                sr=int(s.group(1)), sg=int(s.group(2)), sb=int(s.group(3)),
                punkte=[(int(a), int(b), int(c, 16)) for a, b, c in p[:5]])


def kanaele(v):
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


def vergleich(g, w, name):
    fehler = []
    if (g["w"], g["h"]) != (w["w"], w["h"]):
        fehler.append("Groesse %dx%d statt %dx%d"
                      % (g["w"], g["h"], w["w"], w["h"]))
    verlustfrei = w["art"] in ("png", "bmp")
    punktweise = verlustfrei or w.get("voll", True)
    n = w["w"] * w["h"]
    for k in ("sr", "sg", "sb"):
        d = abs(g[k] - w[k])
        if verlustfrei:
            if d != 0:
                fehler.append("%s %d statt %d" % (k, g[k], w[k]))
        elif d > n:
            fehler.append("%s %d statt %d (%.2f je Bildpunkt)"
                          % (k, g[k], w[k], d / max(1, n)))
    for (gx, gy, gv), (wx, wy, wv) in ([] if not punktweise
                                       else zip(g["punkte"], w["punkte"])):
        if (gx, gy) != (wx, wy):
            fehler.append("Bildpunkt %d,%d statt %d,%d" % (gx, gy, wx, wy))
            continue
        gk, wk = kanaele(gv), kanaele(wv)
        d = max(abs(a - b) for a, b in zip(gk, wk))
        if (verlustfrei and d != 0) or (not verlustfrei and d > 3):
            fehler.append("Bildpunkt %d,%d: %06x statt %06x"
                          % (gx, gy, gv, wv))
    if fehler:
        print("  FAIL  %-16s %s" % (name, "; ".join(fehler[:3])))
        return False
    wie = "Summen und fuenf Bildpunkte"
    if not punktweise:
        wie = "Summen (4:2:0, Farbfilter verschieden)"
    print("  OK    %-16s %s %dx%d, %s stimmen"
          % (name, w["art"], w["w"], w["h"], wie))
    return True


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    if argv[1] != "pruefen":
        for p in argv[1:]:
            print(p, zahlen(p))
        return 0
    text = open(argv[2], "rb").read().decode("latin1")
    gut = 0
    schlecht = 0
    for pfad in argv[3:]:
        name = pfad.split("/")[-1]
        w = zahlen(pfad)
        g = gast(text, name)
        if g is None:
            print("  FAIL  %-16s der Gast hat nichts gesagt" % name)
            schlecht += 1
            continue
        if vergleich(g, w, name):
            gut += 1
        else:
            schlecht += 1
    print("bildref: %d von %d Bildern stimmen mit Pillow ueberein"
          % (gut, gut + schlecht))
    return 0 if schlecht == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
