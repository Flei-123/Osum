#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/themestore/glascheck.py -- die Bilder der Runde GLAS MESSEN.

    glascheck.py mix <bild.png> <alpha>          die Mischung nachrechnen
    glascheck.py var <bild.png>                  Streuung des Leistenstreifens
    glascheck.py kontrast <bild.png> <fg-hex>    Schrift gegen den SCHLECHTESTEN
                                                 gemischten Grund (Anteil >= 1 %),
                                                 Uhr eingeschlossen
    glascheck.py ecke <bild.png> <x> <y> <k>     Farben in einer Ecke zaehlen
    glascheck.py kachel <bild.png> <x> <y> <w> <h> <r>
                                                 Kante, Rundung und was
                                                 ausserhalb der Rundung steht
    glascheck.py diff <a.png> <b.png>            abweichende Bildpunkte

DIE ZWEITE RECHNUNG, UND SIE WEISS NICHTS VON DER ERSTEN.

Die Runde THEMESTORE hat es vorgemacht: `tools/themestore/model.py`
rechnet die Kontraste auf dem Wirt noch einmal, und erst die
Uebereinstimmung zweier Rechnungen, die nichts voneinander wissen, ist
eine Messung.  Fuer diese Runde heisst das: `glass_mix` aus
kernel/ui/wm.fi steht hier ein zweites Mal, aus dem Kommentar dort
abgeschrieben und nicht aus dem Code -- Schluesselfarbe, Abstandsalpha,
Schleier, `blend` mit der Aufrundung `(num + 127) / 255`.  Stimmen die
Bildpunkte unter der Leiste damit ueberein, ist wirklich gemischt
worden und nicht ein Muster aus Loechern gemalt.

Die Leiste wird unten am Bild gesucht: der Streifen der letzten
`--hoehe` Zeilen (Vorgabe 28, die Dicke, mit der jeder Lauf dieser
Abnahme faehrt).  Gemessen wird nur der Teil zwischen `--x0` und `--x1`
-- links sitzen Start- und Fensterknoepfe, rechts die Uhr, und beides
ist Schrift und kein Grund.
"""
import math
import sys
from collections import Counter

from PIL import Image

SCHLEIER = 40          # kernel/ui/wm.fi, const SCHLEIER
VOLL = 96              # der Abstand, ab dem ein Punkt voll deckend ist


def mix8(a, b, al, ia):
    return (a * ia + b * al + 127) // 255


def blend(alt, neu, a):
    if a <= 0:
        return alt
    if a >= 255:
        return neu
    ia = 255 - a
    return tuple(mix8(alt[i], neu[i], a, ia) for i in range(3))


def hell(c):
    return (c[0] * 299 + c[1] * 587 + c[2] * 114) // 1000


def glass_mix(alt, neu, key, alpha):
    """Die Rechnung aus kernel/ui/wm.fi, hier ein zweites Mal."""
    if alpha >= 100:
        return neu
    d = min(sum(abs(neu[i] - key[i]) for i in range(3)), VOLL)
    a = alpha + (100 - alpha) * d // VOLL
    dl = abs(hell(alt) - hell(key))
    if dl > SCHLEIER:
        a = max(a, 100 - SCHLEIER * 100 // dl)
    return blend(alt, neu, a * 255 // 100)


def leiste(im, hoehe, x0, x1):
    w, h = im.size
    # Die obersten zwei Zeilen der Leiste bleiben aussen vor: dort
    # sitzt ihre Kante, und eine Kante ist kein Grund.
    return [(x, y) for x in range(x0, min(x1, w))
            for y in range(h - hoehe + 6, h - 2)]


def wandfarben(im, hoehe, x0, x1):
    """Die zwei Farben des Hintergrundbildes UEBER der Leiste.

    Das mitgelieferte Musterbild hat genau zwei, und beide liegen auch
    unter der Leiste -- ein Schachbrett hoert an ihrer Kante nicht auf.
    """
    w, h = im.size
    top = h - hoehe
    c = Counter(im.getpixel((x, y))
                for x in range(x0, min(x1, w), 3)
                for y in range(max(top - 80, 0), top - 8, 3))
    return [f for f, _ in c.most_common(2)]


def kontrast(a, b):
    def lin(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4

    def lum(c):
        return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])

    l1, l2 = lum(a), lum(b)
    if l1 < l2:
        l1, l2 = l2, l1
    return (l1 + 0.05) / (l2 + 0.05)


def hex2rgb(s):
    s = s.strip().lstrip("#")
    v = int(s, 16)
    return ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    cmd = argv[1]
    opt = {"hoehe": 28, "x0": 300, "x1": 1100, "key": "ffffff", "slack": 2}
    gesetzt = set()
    rest = []
    for a in argv[2:]:
        if a.startswith("--"):
            k, _, v = a[2:].partition("=")
            opt[k] = int(v) if k in ("hoehe", "x0", "x1") else v
            gesetzt.add(k)
        else:
            rest.append(a)
    # RUNDE GLAS (nachtrag): DIE UHR GEHOERT ZUR LEISTE.
    #
    # `x1 = 1100` schnitt die rechten 180 Bildpunkte weg, und genau
    # dort steht die Uhr -- also wurde der Kontrast der Leistenschrift
    # ueberall gemessen, nur nicht an der Stelle, an der auf jeder
    # Aufnahme dieser Runde wirklich Schrift steht. Fuer `kontrast`
    # gilt deshalb die ganze Breite ab `x0`, fuer `mix`, `var` und
    # `diff` bleibt der alte Ausschnitt: die messen den GRUND, und der
    # Grund unter der Uhr traegt Schrift, die ihre Zahlen verfaelschen
    # wuerde. Wer es anders will, sagt `--x1=`.
    if cmd == "kontrast" and "x1" not in gesetzt:
        opt["x1"] = 1 << 30

    if cmd == "diff":
        a = Image.open(rest[0]).convert("RGB")
        b = Image.open(rest[1]).convert("RGB")
        pts = leiste(a, opt["hoehe"], opt["x0"], opt["x1"])
        n = sum(1 for p in pts if a.getpixel(p) != b.getpixel(p))
        print("diff %d von %d" % (n, len(pts)))
        return 0

    im = Image.open(rest[0]).convert("RGB")
    pts = leiste(im, opt["hoehe"], opt["x0"], opt["x1"])
    px = [im.getpixel(p) for p in pts]

    if cmd == "mix":
        alpha = int(rest[1])
        key = hex2rgb(opt["key"])
        walls = wandfarben(im, opt["hoehe"], opt["x0"], opt["x1"])
        erw = set(glass_mix(w, key, key, alpha) for w in walls)
        treffer = sum(1 for p in px if p in erw)
        c = Counter(px)
        print("mix alpha=%d wand=%s erwartet=%s treffer=%d von=%d "
              "prozent=%d farben=%d"
              % (alpha, ",".join("%02x%02x%02x" % w for w in walls),
                 ",".join("%02x%02x%02x" % e for e in sorted(erw)),
                 treffer, len(px), 100 * treffer // max(len(px), 1), len(c)))
        return 0

    if cmd == "var":
        # Die Streuung der Helligkeit, mal hundert. Ein Weichzeichner
        # macht aus zwei Flaechen einen Verlauf: die Zahl MUSS sinken,
        # und sie ist der einzige Beleg, der nicht "sieht doch weich
        # aus" heisst.
        l = [hell(p) for p in px]
        m = sum(l) / len(l)
        var = sum((v - m) ** 2 for v in l) / len(l)
        print("var %d mittel %d n %d farben %d"
              % (int(var * 100), int(m), len(l), len(set(px))))
        return 0

    if cmd == "ecke":
        # DIE ECKE WIRD ZEILE FUER ZEILE ABGETASTET, und das ist der
        # einzige Weg, auf dem "rund" und "kantengeglaettet" zwei
        # verschiedene Zahlen werden.
        #
        # Von links in jede Zeile des Eckquadrats hineingehen und die
        # Stelle merken, an der die Fensterfarbe anfaengt:
        #
        #   tiefe  = wie weit die oberste Zeile spaeter anfaengt als
        #            die unterste. Bei einem rechten Winkel ist das 0,
        #            bei Radius r ungefaehr r -- das ist die Rundung.
        #   weich  = in wie vielen Zeilen der Punkt VOR dieser Stelle
        #            ein Mischton ist, also weder Untergrund noch
        #            Fensterfarbe. Eine Treppe hat dort nichts;
        #            Kantenglaettung hat in fast jeder Zeile etwas.
        #
        # Ohne die zweite Zahl waere eine grob gestufte Rundung von
        # einer geglaetteten nicht zu unterscheiden, und genau das ist
        # die Zusage, um die es geht.
        x, y, k = (int(v) for v in rest[1:4])
        aussen = im.getpixel((x - 6, y + k // 2))
        innen = im.getpixel((x + k + 8, y + k - 1))

        def nah(a, b, tol=12):
            return max(abs(a[i] - b[i]) for i in range(3)) <= tol

        starts, weich = [], 0
        for j in range(k):
            for i in range(k + 8):
                p = im.getpixel((x + i, y + j))
                if not nah(p, aussen):
                    starts.append(i)
                    if i > 0:
                        q = im.getpixel((x + i - 1, y + j))
                        if not nah(q, aussen, 2) and not nah(q, innen, 2):
                            weich += 1
                    break
            else:
                starts.append(k + 8)
        tiefe = max(starts) - min(starts)
        print("ecke tiefe=%d weich=%d zeilen=%d" % (tiefe, weich, len(starts)))
        return 0

    if cmd == "kachel":
        # EINE VORSCHAUKACHEL, GANZ GEMESSEN.
        #
        # Die Kacheln der Seite "Vorlagen" malen ihren Umriss rund und
        # ihren Inhalt eckig -- die Miniaturleiste am rechten Rand lief
        # deshalb an der Rundung vorbei ins Freie ("Tafel", "Studio",
        # Bild 09, ein Farbschlitz bei x=768..774). Drei Zahlen sagen,
        # ob das behoben ist:
        #
        #   links/rechts  die erste und die letzte Spalte, in der auf
        #                 halber Hoehe etwas anderes als der Seitengrund
        #                 steht. Zehn Kacheln untereinander MUESSEN
        #                 dieselben zwei Zahlen melden -- sonst stehen
        #                 sie auf verschiedenen Kanten.
        #   fremd         Bildpunkte in den vier Eckvierteln, die
        #                 AUSSERHALB der Rundung liegen. Genau das war
        #                 der Schlitz, und genau das muss 0 sein.
        #   tiefe         dieselbe Zahl wie `ecke`: dass die Kachel
        #                 ueberhaupt rund ist und nicht nur beschnitten.
        x, y, w, h, r = (int(v) for v in rest[1:6])
        grund = im.getpixel((x - 6, y + h // 2))

        def nah(a, b, tol=12):
            return max(abs(a[i] - b[i]) for i in range(3)) <= tol

        mitte = y + h // 2
        links = rechts = -1
        for i in range(-4, w + 5):
            if not nah(im.getpixel((x + i, mitte)), grund):
                if links < 0:
                    links = x + i
                rechts = x + i
        # Wie weit die Rundung in der Zeile j unter der Kante nach
        # innen greift -- dieselbe Bedingung wie `wlib.ecke_ein` und
        # wie die Eckendeckung in `wlibc.rrect`, hier zum zweiten Mal
        # und aus dem Kommentar dort abgeschrieben. Gerechnet wird mit
        # BILDPUNKTMITTEN (j + 0,5), denn genau so deckt der
        # Rasterizer seine Ecken.
        #
        # `slack` ist die Nachsicht fuer die Kantenglaettung: der
        # Umriss selbst ist zwei Bildpunkte breit verlaufend, und ein
        # Pruefer, der das als Fehler zaehlt, ist ein Pruefer, der
        # Glaettung verbietet. Die oberste und die unterste Zeile
        # bleiben ganz aussen vor -- dort IST der Umriss. Der
        # Farbschlitz, um den es geht, ist sechs Bildpunkte breit und
        # steht in den Zeilen 4..27: er faellt durch beide Nachsichten
        # nicht hindurch.
        slack = int(opt.get("slack", 2))

        def ein(j):
            dy = r - (j + 0.5)
            if dy <= 0:
                return 0
            rest = r * r - dy * dy
            if rest < 0:
                return r
            e = int(math.ceil(r - 0.5 - math.sqrt(rest))) - slack
            return e if e > 0 else 0

        fremd = 0
        starts = []
        for j in range(h):
            d = min(j, h - 1 - j)
            e = ein(d) if 0 < j < h - 1 else 0
            for i in range(e):
                if not nah(im.getpixel((x + i, y + j)), grund):
                    fremd += 1
                if not nah(im.getpixel((x + w - 1 - i, y + j)), grund):
                    fremd += 1
            if j < r:
                s = 0
                while s < r + 8 and nah(im.getpixel((x + s, y + j)), grund):
                    s += 1
                starts.append(s)
        tiefe = (max(starts) - min(starts)) if starts else 0
        print("kachel links=%d rechts=%d fremd=%d tiefe=%d r=%d"
              % (links, rechts, fremd, tiefe, r))
        return 0

    if cmd == "kontrast":
        # DER SCHLECHTESTE GRUND UND NICHT DER HAEUFIGSTE.
        #
        # Bis hierher stand hier `most_common(1)`: gemessen wurde die
        # Farbe, die unter der Leiste am oefte(n)sten vorkommt. Auf
        # einem gemusterten Bild ist das die groessere der beiden
        # Kacheln -- und die Schrift steht nicht nur auf der groesseren.
        # Eine Zusage "4,5:1", die das hellste Viertel des Untergrunds
        # auslaesst, sagt ueber die Lesbarkeit an der Stelle, an der es
        # eng wird, gar nichts.
        #
        # Also: jede Farbe, die mindestens EIN Prozent des Streifens
        # ausmacht, ist ein Grund, auf dem wirklich Schrift stehen
        # kann, und gemessen wird die SCHLECHTESTE davon. Die Schwelle
        # ist nicht Bequemlichkeit, sondern der Filter gegen die
        # Kantenglaettung: die Mischtoene am Rand eines Buchstabens
        # sind zu Hunderten verschieden und jeder einzelne weit unter
        # einem Prozent -- sie sind der Uebergang zwischen Schrift und
        # Grund und kein Grund. Aus demselben Grund fliegen Farben
        # heraus, die der Schriftfarbe selbst nahe sind: das ist die
        # Schrift.
        fg = hex2rgb(rest[1])
        c = Counter(px)
        ges = max(len(px), 1)
        kand = [(f, n) for f, n in c.items()
                if n * 100 >= ges
                and max(abs(f[i] - fg[i]) for i in range(3)) > 40]
        if not kand:
            kand = [c.most_common(1)[0]]
        kand.sort(key=lambda fn: kontrast(fg, fn[0]))
        grund, anz = kand[0]
        best = kand[-1][0]
        k = kontrast(fg, grund)
        print("kontrast %d grund=%02x%02x%02x anteil=%d fg=%02x%02x%02x "
              "kandidaten=%d bester=%d x0=%d x1=%d n=%d"
              % (int(k * 100), grund[0], grund[1], grund[2],
                 100 * anz // ges, fg[0], fg[1], fg[2], len(kand),
                 int(kontrast(fg, best) * 100), opt["x0"],
                 min(opt["x1"], im.size[0]), len(px)))
        return 0

    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
