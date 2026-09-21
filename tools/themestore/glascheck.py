#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/themestore/glascheck.py -- die Bilder der Runde GLAS MESSEN.

    glascheck.py mix <bild.png> <alpha>          die Mischung nachrechnen
    glascheck.py var <bild.png>                  Streuung des Leistenstreifens
                  [--y0=.. --y1=..]              oder, mit y-Grenzen, die eines
                                                 beliebigen Rechtecks -- etwa der
                                                 Flaeche eines durchsichtigen
                                                 Fensters mit Milchglas
    glascheck.py kontrast <bild.png> <fg-hex>    Schrift gegen den SCHLECHTESTEN
                                                 gemischten Grund (Anteil >= 1 %),
                                                 Uhr eingeschlossen
    glascheck.py ecke <bild.png> <x> <y> <k> [ol|or|ul|ur]
                                                 Farben in einer Ecke zaehlen;
                                                 das Wort sagt, WELCHE Ecke des
                                                 Quadrats die aeussere ist
    glascheck.py linien <bild.png> <x> <y> <w> <h> [rand]
                                                 waagerechte Linien in einer
                                                 Karte zaehlen
    glascheck.py kachel <bild.png> <x> <y> <w> <h> <r>
                                                 Kante, Rundung und was
                                                 ausserhalb der Rundung steht
    glascheck.py diff <a.png> <b.png>            abweichende Bildpunkte
    glascheck.py fenster <bild.png> <serial.txt> JEDE Fensterbeschriftung
                                                 gegen ihren GEMISCHTEN Grund
    glascheck.py reiter <bild.png> <serial.txt>  Kantendichte im Band der
                                                 Reiterzeile (fremde Glyphen)

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
import re
import sys
from collections import Counter

from PIL import Image

SCHLEIER = 0          # kernel/ui/wm.fi, const SCHLEIER
# ... und dieselbe Zahl fuer ein gewoehnliches Fenster: kernel/ui/wm.fi,
# const SCHLEIER_WIN.  Sie ist seit fix-r4-2 NULL, und das heisst hier
# wie dort "kein Schleier": ein Fenster holt seine Lesbarkeit nicht
# mehr darueber, dass seine ganze Flaeche deckender wird, sondern ueber
# die TEXTPLATTE -- Ring 3 markiert jeden Bildpunkt, auf dem Schrift
# steht (kernel/user/wlibc.fi, `platte`), und `glass_mix` nimmt ihn
# unveraendert.  Die Flaeche dazwischen ist damit so durchsichtig, wie
# der Regler sagt.  `tools/themestore/run.sh` haelt die beiden Zahlen
# gegeneinander; wer eine aendert, aendert beide.
SCHLEIER_WIN = 0
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


def glass_mix(alt, neu, key, alpha, schleier=SCHLEIER):
    """Die Rechnung aus kernel/ui/wm.fi, hier ein zweites Mal."""
    if alpha >= 100:
        return neu
    d = min(sum(abs(neu[i] - key[i]) for i in range(3)), VOLL)
    a = alpha + (100 - alpha) * d // VOLL
    dl = abs(hell(alt) - hell(key))
    # `schleier == 0` heisst "kein Schleier" und nicht "gar nichts darf
    # durch" -- dieselbe Abfrage wie in kernel/ui/wm.fi, und aus
    # demselben Grund: die Aufloesung nach der Deckung ergibt fuer 0
    # genau 100 Prozent, also das Gegenteil des Gemeinten.
    if schleier > 0 and dl > schleier:
        a = max(a, 100 - schleier * 100 // dl)
    return blend(alt, neu, a * 255 // 100)


def rechteck(im, x0, x1, y0, y1):
    """Ein Rechteck des Bildes als Punktliste -- die EINE Stelle, die
    aus Grenzen Punkte macht.

    Runde GLAS (fix-r4-4): bis hierher gab es nur `leiste`, also nur
    den Streifen am unteren Rand. Das Milchglas liegt seit dieser Runde
    auch unter einem DURCHSICHTIGEN FENSTER, und dessen Ausschnitt ist
    kein Streifen am Bildrand. Gemessen wird er mit derselben Rechnung
    wie die Leiste -- `var` weiss nicht, welches Rechteck es ist.
    """
    w, h = im.size
    return [(x, y) for x in range(max(x0, 0), min(x1, w))
            for y in range(max(y0, 0), min(y1, h))]


def leiste(im, hoehe, x0, x1):
    w, h = im.size
    # Die obersten zwei Zeilen der Leiste bleiben aussen vor: dort
    # sitzt ihre Kante, und eine Kante ist kein Grund.
    return rechteck(im, x0, x1, h - hoehe + 6, h - 2)


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


# ================================== RUNDE GLAS (fix-r3-2): DIE FENSTERSCHRIFT
#
# DIESELBE FRAGE WIE FUER DIE LEISTE, EINE EBENE HOEHER GESTELLT.
#
# Fuer die Leiste gibt es `kontrast` seit dem Nachtrag: die Schrift
# gegen den GEMISCHTEN Grund und nicht gegen die Flaechenfarbe, die in
# der Vorlage steht. Fuer gewoehnliche Fenster fehlte das, und genau
# dort ist es aufgefallen: mit `window_alpha=55` lief die Ausgabe des
# Terminals unter dem Einstellungsfenster quer durch dessen Reiterzeile.
# Die Vorlage sagt "Text #0f172a auf #ffffff, 17,8:1" -- gemalt wurde
# Text auf einer Mischung aus #ffffff und dem, was darunter lag.
#
# WAS DER GRUND EINER BESCHRIFTUNG IST, und warum das nicht die
# haeufigste Farbe ihres Kastens sein darf: in einem engen Kasten um
# eine Zeile Text sind die Mischtoene der Kantenglaettung zu Dutzenden
# vertreten, und jeder einzelne ist dunkler als der Grund. Wer sie
# mitzaehlt, misst die Schrift gegen sich selbst (nachgemessen: 1,43:1
# fuer eine Zeile, die in Wahrheit bei 5,2:1 steht).
#
# Also raeumlich und nicht farblich: TINTE ist, was der Schriftfarbe
# nahe ist; GRUND ist jeder Bildpunkt, der mindestens zwei Bildpunkte
# von jeder Tinte entfernt liegt. Damit fallen die Glaettungsraender
# heraus, der Schatten eines fremden Buchstabens zwischen den Woertern
# aber NICHT -- und der ist es, um den es geht. Gemessen wird der
# SCHLECHTESTE Grund, der mindestens ein Prozent der Flaeche ausmacht.
FENSTERTEXT = re.compile(
    r"wlib: text win=(\d+) kind=(\d+) x=(\d+) base=(\d+) fg=(\d+) bg=(\d+)"
    r" tw=(\d+) ax=(\d+) ay=(\d+)(?: [a-z]+=-?\d+)* t=(.*)")


def fenster(bild, serial, marke="settings: rect name=waa "):
    im = Image.open(bild).convert("RGB")
    roh = open(serial, "rb").read().decode("latin1")
    # Der Stand ZUM ZEITPUNKT DER AUFNAHME: alles nach dem letzten
    # vollstaendigen Bericht der Rechtecke. Dieselbe Regel wie in
    # shotcheck.py, und aus demselben Grund.
    schnitt = roh.rfind(marke)
    schwanz = roh[schnitt:] if schnitt >= 0 else roh
    f = re.findall(r"wlib: font ui px=(\d+) asc=(\d+) h=(\d+)", roh)
    asc, desc = (int(f[-1][1]), int(f[-1][2]) - int(f[-1][1])) if f else (16, 6)
    zeilen = []
    for ln in schwanz.splitlines():
        m = FENSTERTEXT.search(ln)
        if m:
            zeilen.append(m)
    if not zeilen:
        print("fenster KEINE Beschriftung im Mitschnitt -- uitrace aus?")
        return 1
    # Das Fenster mit den meisten Beschriftungen ist das vorderste --
    # dieselbe Wahl wie in shotcheck.py.
    zaehl = Counter(int(m.group(1)) for m in zeilen)
    win = zaehl.most_common(1)[0][0]
    letzte = {}
    for m in zeilen:
        if int(m.group(1)) != win or not m.group(10).strip():
            continue
        letzte[(m.group(2), m.group(10))] = m
    schlecht = None
    n = 0
    aus = []
    for m in letzte.values():
        fg = hex2rgb("%06x" % int(m.group(5)))
        x0 = int(m.group(8)) + int(m.group(3))
        y0 = int(m.group(9)) + int(m.group(4)) - asc
        x1 = min(x0 + int(m.group(7)), im.size[0])
        y1 = min(int(m.group(9)) + int(m.group(4)) + desc, im.size[1])
        if x0 >= x1 or y0 >= y1 or x0 < 0 or y0 < 0:
            continue
        punkte = {}
        for y in range(y0, y1):
            for x in range(x0, x1):
                punkte[(x, y)] = im.getpixel((x, y))
        tinte = set(p for p, c in punkte.items()
                    if max(abs(c[i] - fg[i]) for i in range(3)) <= 60)
        grund = [c for p, c in punkte.items()
                 if not any((p[0] + dx, p[1] + dy) in tinte
                            for dx in range(-2, 3) for dy in range(-2, 3))]
        if not grund:
            continue
        c = Counter(grund)
        ges = len(grund)
        kand = [(f0, k) for f0, k in c.items() if k * 100 >= ges]
        if not kand:
            kand = [c.most_common(1)[0]]
        kand.sort(key=lambda fk: kontrast(fg, fk[0]))
        k = kontrast(fg, kand[0][0])
        n += 1
        aus.append((k, m.group(10)[:28], kand[0][0]))
        if schlecht is None or k < schlecht[0]:
            schlecht = (k, m.group(10)[:28], kand[0][0], len(kand))
    aus.sort()
    print("fenster win=%d beschriftungen=%d schlechteste %d "
          "text='%s' grund=%02x%02x%02x kandidaten=%d"
          % (win, n, int(schlecht[0] * 100), schlecht[1],
             schlecht[2][0], schlecht[2][1], schlecht[2][2], schlecht[3]))
    for k, t, g in aus[:3]:
        print("        %6.2f  '%s' auf %02x%02x%02x" % (k, t, g[0], g[1], g[2]))
    return 0


# ================================================ RUNDE GLAS (fix-r4-2)
# DIE REITERZEILE: KEINE FREMDE GLYPHE, UND DAS WIRD GEZAEHLT.
#
# Der Kontrast einer Reiterbeschriftung sagt, ob SIE zu lesen ist. Er
# sagt nichts darueber, ob NEBEN ihr noch ein zweiter Text steht: der
# Schatten eines fremden Buchstabens zwischen zwei Reitern hat gegen
# den Reiternamen gar keinen Kontrast zu halten, er gehoert einfach
# nicht dorthin.
#
# Gezaehlt wird deshalb die KANTENDICHTE im Band der Reiterzeile --
# benachbarte Bildpunkte, die sich um mehr als `--slack` Stufen
# unterscheiden. Ein Buchstabe ist nichts als Kanten; eine Flaeche hat
# keine. Die Zahl allein sagt nichts (die Reiter selbst haben Kanten),
# der VERGLEICH sagt alles: derselbe Stand mit `window_alpha=100` hat
# genau die Kanten, die dorthin gehoeren, und ein durchsichtiges
# Fenster mit deckender Reiterzeile muss dieselben haben.
#
# Das Band kommt aus dem Mitschnitt und nicht aus einer geratenen
# Hoehe: `wlib: tab ... ax= ay= w= h=` meldet jeder Reiter selbst.
def reiter(bild, serial):
    im = Image.open(bild).convert("RGB")
    roh = open(serial, "rb").read().decode("latin1")
    tabs = re.findall(r"wlib: tab i=\d+ x=\d+ y=\d+ w=(\d+) h=(\d+)"
                      r" ax=(\d+) ay=(\d+)", roh)
    if not tabs:
        print("reiter KEIN Reiter im Mitschnitt -- uitrace aus?")
        return 1
    x0 = min(int(t[2]) for t in tabs)
    y0 = min(int(t[3]) for t in tabs)
    x1 = max(int(t[2]) + int(t[0]) for t in tabs)
    y1 = max(int(t[3]) + int(t[1]) for t in tabs)
    x1 = min(x1, im.size[0])
    y1 = min(y1, im.size[1])
    kanten = 0
    punkte = 0
    for y in range(y0, y1):
        for x in range(x0, x1 - 1):
            a = im.getpixel((x, y))
            b = im.getpixel((x + 1, y))
            punkte += 1
            if max(abs(a[i] - b[i]) for i in range(3)) > 24:
                kanten += 1
    print("reiter band=%d,%d,%d,%d kanten=%d punkte=%d"
          % (x0, y0, x1, y1, kanten, punkte))
    return 0


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
            opt[k] = int(v) if k in ("hoehe", "x0", "x1", "y0", "y1") else v
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

    if cmd == "fenster":
        return fenster(rest[0], rest[1])

    if cmd == "reiter":
        return reiter(rest[0], rest[1])

    if cmd == "diff":
        a = Image.open(rest[0]).convert("RGB")
        b = Image.open(rest[1]).convert("RGB")
        pts = leiste(a, opt["hoehe"], opt["x0"], opt["x1"])
        n = sum(1 for p in pts if a.getpixel(p) != b.getpixel(p))
        print("diff %d von %d" % (n, len(pts)))
        return 0

    im = Image.open(rest[0]).convert("RGB")
    # RUNDE GLAS (fix-r4-4): EIN AUSSCHNITT, DER KEIN STREIFEN IST.
    #
    # Ohne `--y0/--y1` ist der Ausschnitt der Leistenstreifen wie
    # bisher, Bildpunkt fuer Bildpunkt derselbe. Mit ihnen ist es ein
    # Rechteck irgendwo im Bild -- gebraucht wird das fuer das
    # Milchglas unter einem DURCHSICHTIGEN FENSTER, das seit dieser
    # Runde auch eines bekommt: auf 28 Bildpunkten Leiste MISST man
    # einen Weichzeichner, auf einer Fensterflaeche SIEHT man ihn.
    if "y0" in gesetzt or "y1" in gesetzt:
        pts = rechteck(im, opt["x0"], opt["x1"],
                      opt.get("y0", 0), opt.get("y1", im.size[1]))
    else:
        pts = leiste(im, opt["hoehe"], opt["x0"], opt["x1"])
    # ============================= RUNDE GLAS (NACHTRAG 2): --felder
    #
    # DIE LESBARKEIT WIRD DORT GEMESSEN, WO SCHRIFT STEHT -- UND NICHT
    # IRGENDWO AUF DER LEISTE.
    #
    # Solange die Leiste eine Untergrenze der Deckkraft hatte, war der
    # ganze Streifen gleich hell, und "der schlechteste Grund im
    # Streifen" war derselbe wie "der Grund unter der Schrift". Seit
    # die Deckung dort sitzt, wo sie hingehoert (die Textplatte aus
    # `wlibc.platte`, die Ring 0 in `glass_mix` unveraendert
    # durchlaesst), sind das zwei verschiedene Dinge: zwischen den
    # Beschriftungen ist die Leiste so durchsichtig, wie der Regler
    # sagt, und dort steht kein Buchstabe, dessen Lesbarkeit man
    # beurteilen koennte. Eine Zusage, die den leeren Teil der Leiste
    # gegen die Schriftfarbe haelt, misst die Lesbarkeit von nichts.
    #
    # `--felder=x,base,tw;...` sind die Felder, die die Leiste selbst
    # auf der seriellen Leitung meldet (`taskbar: text ... x= base=
    # tw=`), `--ascent` ihre Oberlaenge. Das Rechteck ist genau das,
    # das `wlibc.text_at` als Platte setzt: eine Zeile ueber der
    # Oberlaenge bis zwei unter der Grundlinie.
    if opt.get("felder"):
        asc = int(opt.get("ascent", 12))
        unten = int(opt.get("unter", 4))
        bar_y = im.size[1] - opt["hoehe"]
        erlaubt = []
        for f in str(opt["felder"]).split(";"):
            if not f.strip():
                continue
            teile = f.split(",")
            fx, fb, ftw = (int(v) for v in teile[:3])
            # EINEN BILDPUNKT ENGER ALS DIE PLATTE, ABSICHTLICH: die
            # Platte ist rundum einen Punkt groesser als das Feld,
            # damit ihre Kante nicht zu sehen ist, und genau dieser
            # Saum ist eine Mischung aus Platte und durchsichtiger
            # Leiste. Er ist kein Grund, auf dem Schrift steht.
            y0 = bar_y + fb - asc
            y1 = bar_y + fb + unten - 1
            # VIERTES GLIED: DIE SCHRIFTFARBE DIESES FELDES.
            #
            # Die drei Felder der Leiste sind nicht gleich beschriftet:
            # der Knopf des VORDERSTEN Fensters traegt weisse Schrift
            # auf der Akzentfarbe, Start und Uhr dunkle Schrift auf der
            # Platte. Wer alle drei gegen dieselbe Schriftfarbe haelt,
            # meldet fuer den Knopf den Kontrast einer Farbe, die dort
            # gar nicht steht -- gemessen 3,45:1 gegen die Akzentflaeche,
            # auf der in Wahrheit Weiss mit 4,8:1 steht.
            erlaubt.append((fx, y0, fx + ftw, y1,
                            hex2rgb(teile[3]) if len(teile) > 3 else None))
        pts = [p for p in pts
               if any(a <= p[0] <= c and b <= p[1] <= d
                      for a, b, c, d, _f in erlaubt)]
        opt["_felder"] = erlaubt
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

    if cmd == "linien":
        # DIE WAAGERECHTEN LINIEN IN EINER KARTE, GEZAEHLT (fix-r4-3).
        #
        # Die Frage dahinter: umrandet ein grosser Radius eine Karte
        # zweimal? Angeschaut war das auf Bild 03 eine zwei Bildpunkte
        # hohe Linie unter der Karte, und angeschaut kann man das nicht
        # entscheiden. Gezaehlt schon: eine Bildzeile gilt als LINIE,
        # wenn sie ueber den ganzen gemessenen Ausschnitt hinweg vom
        # Kartengrund abweicht. Dieselbe Karte bei Radius 0 und bei 24
        # muss dieselbe Zahl liefern.
        #
        # `rand` ist der Saum, der auf beiden Seiten aussen vor bleibt,
        # und er ist der Grund, warum diese Zahl ueberhaupt vergleichbar
        # ist: eine Rundung frisst an JEDEM Ende einer Linie bis zu
        # `radius` Bildpunkte (der Rahmen eines Eingabefeldes laeuft bei
        # Radius 24 erst 24 Bildpunkte spaeter los). Wer bis an die
        # Kartenkante misst, zaehlt deshalb bei Radius 24 weniger
        # Linien und haelt den Unterschied fuer einen Fehler. 56 ist
        # der groesste Radius dieser Runde plus der Innenabstand der
        # Spalte.
        # WAS EINE LINIE IST, und warum nicht "weicht vom Grund ab":
        # in einer Karte stehen Flaechen (Eingabefeld, Liste, Knopf) in
        # ihrer eigenen Farbe, und gegen den Kartengrund gemessen waere
        # JEDE ihrer Zeilen eine Linie. Eine Linie ist etwas anderes:
        # ein DUENNER Streifen. Gezaehlt wird deshalb die Zeile, die
        # sich ueber ihre ganze Laenge von der Zeile zwei darueber UND
        # von der zwei darunter unterscheidet. Eine Flaeche liefert
        # damit nur ihre zwei Kanten, eine doppelt gemalte Kante zwei
        # Zeilen -- genau die Zahl, um die es geht.
        x, y, w, h = (int(v) for v in rest[1:5])
        rand = int(rest[5]) if len(rest) > 5 else 56
        x0, x1 = x + rand, x + w - rand
        if x1 - x0 < 20:
            print("linien=0 breite=0 -- Ausschnitt zu schmal")
            return 0

        def weg(a, b):
            return max(abs(a[k] - b[k]) for k in range(3)) > 12

        n = 0
        for j in range(y + 3, y + h - 3):
            treffer = 0
            for i in range(x0, x1):
                p = im.getpixel((i, j))
                if weg(p, im.getpixel((i, j - 2))) \
                        and weg(p, im.getpixel((i, j + 2))):
                    treffer += 1
            if treffer * 10 >= (x1 - x0) * 9:
                n += 1
        print("linien=%d breite=%d" % (n, x1 - x0))
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
        # WELCHE DER VIER ECKEN, und warum das ein Wort und kein
        # zweiter Befehl ist (fix-r4-3): die Rechnung ist fuer alle
        # vier dieselbe, nur die Richtung, in der "nach innen" zeigt,
        # ist eine andere. Ein zweiter Befehl daneben waere dieselbe
        # Sache ein zweites Mal -- also wird das Quadrat gespiegelt
        # und nicht die Messung verdoppelt. `ol` ist die Vorgabe und
        # damit Aufruf fuer Aufruf das, was vor diesem Zusatz stand.
        wo = rest[4] if len(rest) > 4 else "ol"
        rechts = wo in ("or", "ur")
        unten = wo in ("ul", "ur")

        def P(i, j):
            X = (x + k - 1 - i) if rechts else (x + i)
            Y = (y + k - 1 - j) if unten else (y + j)
            return im.getpixel((X, Y))

        aussen = P(-6, k // 2)
        innen = P(k + 8, k - 1)

        def nah(a, b, tol=12):
            return max(abs(a[i] - b[i]) for i in range(3)) <= tol

        starts, weich = [], 0
        for j in range(k):
            for i in range(k + 8):
                p = P(i, j)
                if not nah(p, aussen):
                    starts.append(i)
                    if i > 0:
                        q = P(i - 1, j)
                        if not nah(q, aussen, 2) and not nah(q, innen, 2):
                            weich += 1
                    break
            else:
                starts.append(k + 8)
        tiefe = max(starts) - min(starts)
        print("ecke %s tiefe=%d weich=%d zeilen=%d"
              % (wo, tiefe, weich, len(starts)))
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
        # UND DIE FLAECHE SELBST, BILDPUNKT FUER BILDPUNKT.
        #
        # `fremd` sieht nach AUSSEN und hat damit den halben Fehler
        # nicht gesehen: eine Kachel, die ihre Flaeche aus einem
        # anderen Rasterer holt als ihren Rahmen, verliert Bildpunkte
        # auch nach INNEN. Gemessen an Bild 09 (Stand vor diesem
        # Nachtrag): `fuib.tafel` beschneidet ein Rechteck, das oben aus
        # dem Malband herausragt, auf die Bandkante und rundet danach
        # die Ecken des BESCHNITTENEN Rechtecks -- mitten in der Kachel
        # "Mitternacht" stand deshalb ein acht Bildpunkte breiter Keil
        # in der Farbe des Seitengrunds (x=331..338, Zeilen 229..233),
        # der wie ein verlorenes Zeichen aussah.
        #
        # Die Probe nimmt den LINKEN RAND der Kachel: die Spalten 4..7
        # liegen hinter dem Auswahlring (drei Bildpunkte breit,
        # `M_FOCUS + 1`) und vor dem Namen (der bei x+8 anfaengt), und
        # in den Zeilen zwischen den beiden Rundungen liegt dort NICHTS
        # ausser der Flaeche der Kachel. Was dort nicht die haeufigste
        # Farbe dieser Spalten ist, ist ein Loch.
        #
        # Dazu zwei waagerechte Streifen zwischen dem Rahmen und dem
        # Namen (Zeile 5..7 von oben und von unten, im mittleren
        # Drittel der Breite): dort liegt weder der Name, der erst bei
        # x+8 anfaengt und mittig sitzt, noch die Vorschau, die ganz
        # rechts sitzt -- und ein Keil an der OBEREN Bandkante faellt
        # durch die senkrechte Probe allein nicht auf.
        probe = [(x + i, y + j)
                 for j in range(r + 1, h - r - 1) for i in range(4, 8)]
        for j in (5, 6, 7, h - 8, h - 7, h - 6):
            for i in range(w // 3, w // 3 + 40):
                probe.append((x + i, y + j))
        innen = 0
        if probe:
            flaeche = Counter(im.getpixel(p) for p in probe).most_common(1)[0][0]
            innen = sum(1 for p in probe if not nah(im.getpixel(p), flaeche, 24))
        print("kachel links=%d rechts=%d fremd=%d innen=%d probe=%d tiefe=%d r=%d"
              % (links, rechts, fremd, innen, len(probe), tiefe, r))
        return 0

    if cmd == "kontrast" and opt.get("_felder"):
        # JE FELD SEINE EIGENE SCHRIFTFARBE, UND GEMELDET WIRD DAS
        # SCHLECHTESTE FELD.
        #
        # Das ist dieselbe Rechnung wie unten, nur feldweise: die
        # Glaettungstoene fliegen ueber die Verbindungslinie raus, der
        # schlechteste verbleibende Grund zaehlt, und von den Feldern
        # zaehlt das schwaechste. Ein Mittelwert waere hier falsch --
        # unlesbar ist eine Beschriftung schon dann, wenn EINE es ist.
        vor = hex2rgb(rest[1])
        schlecht = None
        zeile = []
        for (a, b, cc, d, ffg) in opt["_felder"]:
            fg = ffg if ffg else vor
            # DAS GANZE FELD, UND DER GRUND IST, WAS DARIN DIE FLAECHE
            # AUSMACHT.
            #
            # Ein Umweg ueber das umschliessende Rechteck der
            # Schriftpunkte funktioniert nur, solange die Schrift dunkel
            # ist: bei WEISSER Schrift auf dem Knopf des vordersten
            # Fensters ist die Textplatte selbst weiss, sie gilt dann als
            # "Schriftpunkt", und das Rechteck wird so gross wie das
            # Feld. Also andersherum gerechnet -- der Grund ist die
            # Farbe, die im Feld die FLAECHE traegt, und eine Flaeche
            # macht mindestens ein Fuenftel des Feldes aus. Alles
            # Seltenere ist Rand oder Glaettung.

            # Auf den Bildrand geklemmt: ein Feld, das die Leiste an
            # den rechten Rand setzt, reicht mit seinem Platz ueber das
            # Bild hinaus, und ein Absturz ist keine Messung.
            fpx = [im.getpixel((i, j))
                   for i in range(max(a, 0), min(cc, im.size[0] - 1) + 1)
                   for j in range(max(b, 0), min(d, im.size[1] - 1) + 1)]
            if not fpx:
                continue
            cnt = Counter(fpx)
            ges = len(fpx)
            haeufig = cnt.most_common(1)[0][0]

            def auf_linie(f, fg=fg, haeufig=haeufig):
                dv = [haeufig[i] - fg[i] for i in range(3)]
                ll = sum(v * v for v in dv)
                if ll == 0:
                    return False
                t = sum((f[i] - fg[i]) * dv[i] for i in range(3)) / ll
                t = max(0.0, min(1.0, t))
                ab = sum((f[i] - fg[i] - t * dv[i]) ** 2 for i in range(3))
                return ab <= 12 * 12

            kand = [(f, n) for f, n in cnt.items()
                    if n * 5 >= ges
                    and max(abs(f[i] - fg[i]) for i in range(3)) > 40
                    and not auf_linie(f)]
            if not kand:
                kand = [(haeufig, cnt[haeufig])]
            kand.sort(key=lambda fn: kontrast(fg, fn[0]))
            g, anz = kand[0]
            k = kontrast(fg, g)
            zeile.append("x%d=%d" % (a, int(k * 100)))
            if schlecht is None or k < schlecht[0]:
                schlecht = (k, g, anz, ges, fg, len(kand))
        k, g, anz, ges, fg, nk = schlecht
        print("kontrast %d grund=%02x%02x%02x anteil=%d fg=%02x%02x%02x "
              "kandidaten=%d felder=%d %s"
              % (int(k * 100), g[0], g[1], g[2], 100 * anz // max(ges, 1),
                 fg[0], fg[1], fg[2], nk, len(opt["_felder"]),
                 " ".join(zeile)))
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
        # Mit `--felder` ist der Ausschnitt klein (ein paar hundert
        # Bildpunkte statt dreissigtausend), und ein Prozent davon sind
        # eine Handvoll Punkte -- also genau die Groessenordnung, in der
        # die Kantenglaettung der Buchstaben lebt. Auf einem so kleinen
        # Ausschnitt ist die Schwelle deshalb fuenf Prozent.
        schwelle = 5 if opt.get("felder") else 1

        # UND DIE KANTENGLAETTUNG FLIEGT RAUS, AUCH WENN SIE HAEUFIG IST.
        #
        # Der Filter darueber ("weit genug weg von der Schriftfarbe")
        # reicht auf dem ganzen Streifen, weil ein Glaettungston dort
        # nie ein Prozent erreicht. Auf dem kleinen Ausschnitt eines
        # Textfeldes erreicht er sieben bis neun, und dann wird der
        # dunkelste Randton eines Buchstabens als "Grund" gemeldet und
        # gegen die Schriftfarbe gehalten -- gemessen an "Start" auf
        # einer VOLL DECKENDEN Leiste: 42 Bildpunkte (75, 81, 95)
        # zwischen Schrift (15, 23, 42) und Platte (255, 255, 255).
        # Dieselben 42 Punkte stehen auf der durchsichtigen Leiste,
        # also ist das kein Durchscheinen, sondern der Umriss.
        #
        # Ein Glaettungston liegt auf der Verbindungslinie zwischen
        # Schriftfarbe und Grund. Genau das wird geprueft: der Abstand
        # der Farbe von dieser Strecke. Eine Farbe, die WIRKLICH
        # durchscheinender Untergrund ist, liegt daneben -- sie traegt
        # den Farbton des Bildes.
        haeufig = c.most_common(1)[0][0]

        def auf_linie(f):
            d = [haeufig[i] - fg[i] for i in range(3)]
            ll = sum(v * v for v in d)
            if ll == 0:
                return False
            t = sum((f[i] - fg[i]) * d[i] for i in range(3)) / ll
            t = max(0.0, min(1.0, t))
            ab = sum((f[i] - fg[i] - t * d[i]) ** 2 for i in range(3))
            return ab <= 12 * 12

        kand = [(f, n) for f, n in c.items()
                if n * 100 >= ges * schwelle
                and max(abs(f[i] - fg[i]) for i in range(3)) > 40
                and not auf_linie(f)]
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
