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

SCHLEIER = 0
SCHLEIER_WIN = 0
VOLL = 96


def mix8(a, b, al, ia):
    return (a * ia + b * al + 127) // 255


def blend(alt, new_2, a):
    if a <= 0:
        return alt
    if a >= 255:
        return new_2
    ia = 255 - a
    return tuple(mix8(alt[i], new_2[i], a, ia) for i in range(3))


def bright(c):
    return (c[0] * 299 + c[1] * 587 + c[2] * 114) // 1000


def glass_mix(alt, new_2, key, alpha, schleier=SCHLEIER):
    """Die Rechnung aus kernel/ui/wm.fi, hier ein zweites Mal."""
    if alpha >= 100:
        return new_2
    d = min(sum(abs(new_2[i] - key[i]) for i in range(3)), VOLL)
    a = alpha + (100 - alpha) * d // VOLL
    dl = abs(bright(alt) - bright(key))
    if schleier > 0 and dl > schleier:
        a = max(a, 100 - schleier * 100 // dl)
    return blend(alt, new_2, a * 255 // 100)


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


def contrast_2(a, b):
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


FENSTERTEXT = re.compile(
    r"wlib: text win=(\d+) kind=(\d+) x=(\d+) base=(\d+) fg=(\d+) bg=(\d+)"
    r" tw=(\d+) ax=(\d+) ay=(\d+)(?: [a-z]+=-?\d+)* t=(.*)")


def window_2(image_2, serial, brand_2="settings: rect name=waa "):
    im = Image.open(image_2).convert("RGB")
    roh = open(serial, "rb").read().decode("latin1")
    schnitt = roh.rfind(brand_2)
    tail_2 = roh[schnitt:] if schnitt >= 0 else roh
    f = re.findall(r"wlib: font ui px=(\d+) asc=(\d+) h=(\d+)", roh)
    asc, desc = (int(f[-1][1]), int(f[-1][2]) - int(f[-1][1])) if f else (16, 6)
    zeilen = []
    for ln in tail_2.splitlines():
        m = FENSTERTEXT.search(ln)
        if m:
            zeilen.append(m)
    if not zeilen:
        print("window NO label in the capture -- uitrace off?")
        return 1
    zaehl = Counter(int(m.group(1)) for m in zeilen)
    win = zaehl.most_common(1)[0][0]
    last_3 = {}
    for m in zeilen:
        if int(m.group(1)) != win or not m.group(10).strip():
            continue
        last_3[(m.group(2), m.group(10))] = m
    bad_2 = None
    n = 0
    aus = []
    for m in last_3.values():
        fg = hex2rgb("%06x" % int(m.group(5)))
        x0 = int(m.group(8)) + int(m.group(3))
        y0 = int(m.group(9)) + int(m.group(4)) - asc
        x1 = min(x0 + int(m.group(7)), im.size[0])
        y1 = min(int(m.group(9)) + int(m.group(4)) + desc, im.size[1])
        if x0 >= x1 or y0 >= y1 or x0 < 0 or y0 < 0:
            continue
        points_2 = {}
        for y in range(y0, y1):
            for x in range(x0, x1):
                points_2[(x, y)] = im.getpixel((x, y))
        tinte = set(p for p, c in points_2.items()
                    if max(abs(c[i] - fg[i]) for i in range(3)) <= 60)
        reason_2 = [c for p, c in points_2.items()
                 if not any((p[0] + dx, p[1] + dy) in tinte
                            for dx in range(-2, 3) for dy in range(-2, 3))]
        if not reason_2:
            continue
        c = Counter(reason_2)
        ges = len(reason_2)
        haeufig = c.most_common(1)[0][0]
        dv = [haeufig[i] - fg[i] for i in range(3)]
        ll = sum(v * v for v in dv)

        def auf_line(f):
            if ll == 0 or f == haeufig:
                return False
            t = sum((f[i] - fg[i]) * dv[i] for i in range(3)) / ll
            t = max(0.0, min(1.0, t))
            ab = sum((f[i] - fg[i] - t * dv[i]) ** 2 for i in range(3))
            return ab <= 12 * 12

        kand = [(f0, k) for f0, k in c.items()
                if k * 100 >= ges and not auf_line(f0)]
        if not kand:
            kand = [c.most_common(1)[0]]
        kand.sort(key=lambda fk: contrast_2(fg, fk[0]))
        k = contrast_2(fg, kand[0][0])
        n += 1
        aus.append((k, m.group(10)[:28], kand[0][0]))
        if bad_2 is None or k < bad_2[0]:
            bad_2 = (k, m.group(10)[:28], kand[0][0], len(kand))
    aus.sort()
    print("fenster win=%d beschriftungen=%d schlechteste %d "
          "text='%s' grund=%02x%02x%02x kandidaten=%d"
          % (win, n, int(bad_2[0] * 100), bad_2[1],
             bad_2[2][0], bad_2[2][1], bad_2[2][2], bad_2[3]))
    for k, t, g in aus[:3]:
        print("        %6.2f  '%s' auf %02x%02x%02x" % (k, t, g[0], g[1], g[2]))
    return 0


def tab_2(image_2, serial):
    im = Image.open(image_2).convert("RGB")
    roh = open(serial, "rb").read().decode("latin1")
    tabs = re.findall(r"wlib: tab i=\d+ x=\d+ y=\d+ w=(\d+) h=(\d+)"
                      r" ax=(\d+) ay=(\d+)", roh)
    if not tabs:
        print("tab NO tab in the capture -- uitrace off?")
        return 1
    x0 = min(int(t[2]) for t in tabs)
    y0 = min(int(t[3]) for t in tabs)
    x1 = max(int(t[2]) + int(t[0]) for t in tabs)
    y1 = max(int(t[3]) + int(t[1]) for t in tabs)
    x1 = min(x1, im.size[0])
    y1 = min(y1, im.size[1])
    edges_2 = 0
    points_2 = 0
    for y in range(y0, y1):
        for x in range(x0, x1 - 1):
            a = im.getpixel((x, y))
            b = im.getpixel((x + 1, y))
            points_2 += 1
            if max(abs(a[i] - b[i]) for i in range(3)) > 24:
                edges_2 += 1
    print("reiter band=%d,%d,%d,%d kanten=%d punkte=%d"
          % (x0, y0, x1, y1, edges_2, points_2))
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
    if cmd == "kontrast" and "x1" not in gesetzt:
        opt["x1"] = 1 << 30

    if cmd == "fenster":
        return window_2(rest[0], rest[1])

    if cmd == "reiter":
        return tab_2(rest[0], rest[1])

    if cmd == "diff":
        a = Image.open(rest[0]).convert("RGB")
        b = Image.open(rest[1]).convert("RGB")
        pts = leiste(a, opt["hoehe"], opt["x0"], opt["x1"])
        n = sum(1 for p in pts if a.getpixel(p) != b.getpixel(p))
        print("diff %d von %d" % (n, len(pts)))
        return 0

    im = Image.open(rest[0]).convert("RGB")
    if "y0" in gesetzt or "y1" in gesetzt:
        pts = rechteck(im, opt["x0"], opt["x1"],
                      opt.get("y0", 0), opt.get("y1", im.size[1]))
    else:
        pts = leiste(im, opt["hoehe"], opt["x0"], opt["x1"])
    if opt.get("felder"):
        asc = int(opt.get("ascent", 12))
        bottom = int(opt.get("unter", 4))
        bar_y = im.size[1] - opt["hoehe"]
        erlaubt = []
        for f in str(opt["felder"]).split(";"):
            if not f.strip():
                continue
            parts = f.split(",")
            fx, fb, ftw = (int(v) for v in parts[:3])
            y0 = bar_y + fb - asc
            y1 = bar_y + fb + bottom - 1
            erlaubt.append((fx, y0, fx + ftw, y1,
                            hex2rgb(parts[3]) if len(parts) > 3 else None))
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
        l = [bright(p) for p in px]
        m = sum(l) / len(l)
        var = sum((v - m) ** 2 for v in l) / len(l)
        print("var %d mittel %d n %d farben %d"
              % (int(var * 100), int(m), len(l), len(set(px))))
        return 0

    if cmd == "linien":
        x, y, w, h = (int(v) for v in rest[1:5])
        rand = int(rest[5]) if len(rest) > 5 else 56
        x0, x1 = x + rand, x + w - rand
        if x1 - x0 < 20:
            print("lines=0 width=0 -- crop too narrow")
            return 0

        def gone(a, b):
            return max(abs(a[k] - b[k]) for k in range(3)) > 12

        n = 0
        for j in range(y + 3, y + h - 3):
            treffer = 0
            for i in range(x0, x1):
                p = im.getpixel((i, j))
                if gone(p, im.getpixel((i, j - 2))) \
                        and gone(p, im.getpixel((i, j + 2))):
                    treffer += 1
            if treffer * 10 >= (x1 - x0) * 9:
                n += 1
        print("linien=%d breite=%d" % (n, x1 - x0))
        return 0

    if cmd == "ecke":
        x, y, k = (int(v) for v in rest[1:4])
        wo = rest[4] if len(rest) > 4 else "ol"
        right = wo in ("or", "ur")
        bottom = wo in ("ul", "ur")

        def P(i, j):
            X = (x + k - 1 - i) if right else (x + i)
            Y = (y + k - 1 - j) if bottom else (y + j)
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
        x, y, w, h, r = (int(v) for v in rest[1:6])
        reason_2 = im.getpixel((x - 6, y + h // 2))

        def nah(a, b, tol=12):
            return max(abs(a[i] - b[i]) for i in range(3)) <= tol

        mitte = y + h // 2
        links = right = -1
        for i in range(-4, w + 5):
            if not nah(im.getpixel((x + i, mitte)), reason_2):
                if links < 0:
                    links = x + i
                right = x + i
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

        foreign = 0
        starts = []
        for j in range(h):
            d = min(j, h - 1 - j)
            e = ein(d) if 0 < j < h - 1 else 0
            for i in range(e):
                if not nah(im.getpixel((x + i, y + j)), reason_2):
                    foreign += 1
                if not nah(im.getpixel((x + w - 1 - i, y + j)), reason_2):
                    foreign += 1
            if j < r:
                s = 0
                while s < r + 8 and nah(im.getpixel((x + s, y + j)), reason_2):
                    s += 1
                starts.append(s)
        tiefe = (max(starts) - min(starts)) if starts else 0
        probe = [(x + i, y + j)
                 for j in range(r + 1, h - r - 1) for i in range(4, 8)]
        for j in (5, 6, 7, h - 8, h - 7, h - 6):
            for i in range(w // 3, w // 3 + 40):
                probe.append((x + i, y + j))
        innen = 0
        if probe:
            area = Counter(im.getpixel(p) for p in probe).most_common(1)[0][0]
            innen = sum(1 for p in probe if not nah(im.getpixel(p), area, 24))
        print("kachel links=%d rechts=%d fremd=%d innen=%d probe=%d tiefe=%d r=%d"
              % (links, right, foreign, innen, len(probe), tiefe, r))
        return 0

    if cmd == "kontrast" and opt.get("_felder"):
        vor = hex2rgb(rest[1])
        bad_2 = None
        line_3 = []
        for (a, b, cc, d, ffg) in opt["_felder"]:
            fg = ffg if ffg else vor

            fpx = [im.getpixel((i, j))
                   for i in range(max(a, 0), min(cc, im.size[0] - 1) + 1)
                   for j in range(max(b, 0), min(d, im.size[1] - 1) + 1)]
            if not fpx:
                continue
            cnt = Counter(fpx)
            ges = len(fpx)
            haeufig = cnt.most_common(1)[0][0]

            def auf_line(f, fg=fg, haeufig=haeufig):
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
                    and not auf_line(f)]
            if not kand:
                kand = [(haeufig, cnt[haeufig])]
            kand.sort(key=lambda fn: contrast_2(fg, fn[0]))
            g, anz = kand[0]
            k = contrast_2(fg, g)
            line_3.append("x%d=%d" % (a, int(k * 100)))
            if bad_2 is None or k < bad_2[0]:
                bad_2 = (k, g, anz, ges, fg, len(kand))
        k, g, anz, ges, fg, nk = bad_2
        print("kontrast %d grund=%02x%02x%02x anteil=%d fg=%02x%02x%02x "
              "kandidaten=%d felder=%d %s"
              % (int(k * 100), g[0], g[1], g[2], 100 * anz // max(ges, 1),
                 fg[0], fg[1], fg[2], nk, len(opt["_felder"]),
                 " ".join(line_3)))
        return 0

    if cmd == "kontrast":
        fg = hex2rgb(rest[1])
        c = Counter(px)
        ges = max(len(px), 1)
        schwelle = 5 if opt.get("felder") else 1

        haeufig = c.most_common(1)[0][0]

        def auf_line(f):
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
                and not auf_line(f)]
        if not kand:
            kand = [c.most_common(1)[0]]
        kand.sort(key=lambda fn: contrast_2(fg, fn[0]))
        reason_2, anz = kand[0]
        best = kand[-1][0]
        k = contrast_2(fg, reason_2)
        print("kontrast %d grund=%02x%02x%02x anteil=%d fg=%02x%02x%02x "
              "kandidaten=%d bester=%d x0=%d x1=%d n=%d"
              % (int(k * 100), reason_2[0], reason_2[1], reason_2[2],
                 100 * anz // ges, fg[0], fg[1], fg[2], len(kand),
                 int(contrast_2(fg, best) * 100), opt["x0"],
                 min(opt["x1"], im.size[0]), len(px)))
        return 0

    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
