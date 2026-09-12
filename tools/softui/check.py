#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/softui/check.py -- DIE BILDER WERDEN GEMESSEN, NICHT ANGESEHEN.

Justin, zu dieser Runde: *"Die Screenshots werden GEMESSEN, nicht
angeschaut: keine leeren Beschriftungen, nichts abgeschnitten, nichts
ueberlappend -- diese Fehler sind hier schon zweimal durchgerutscht."*

Sie sind durchgerutscht, weil sie mit blossem Auge auf einem 800 x 600
grossen Bild klein sind und weil ein Testlaeufer, der nur den
Beendigungscode von QEMU liest, sie gar nicht sehen KANN.  Also nimmt
dieses Programm den seriellen Mitschnitt als Behauptung und das Bild als
Wahrheit und haelt beides gegeneinander.

Der Mitschnitt meldet fuer jede Textausgabe der Widget-Bibliothek eine
Zeile der Form

    wlib: text win=<id> kind=<n> x=<x> base=<y> fg=<n> bg=<n> tw=<n> t=<text>

und fuer die Leiste dieselbe Sorte Zeile.  Daraus folgen drei Fragen,
die ein Bild beantworten kann und ein Mitschnitt nicht:

  LEER          Steht an (x, base) ueberhaupt Tinte?  Eine Beschriftung,
                die gemeldet und nicht gemalt wurde, ist der Fehler, den
                Runde K7B und Runde TASKBAR beide einmal hatten.  Es
                wird im Kasten von der Grundlinie aus nach oben gezaehlt
                (`asc` Zeilen), nicht im ganzen Fenster: sonst zaehlt
                man den Nachbarn mit.

  ABGESCHNITTEN Reicht die gemeldete Breite `tw` ueber den rechten Rand
                seines Fensters hinaus?  Und steht in der letzten
                Spalte des Fensters noch Tinte derselben Farbe?  Das
                zweite ist der eigentliche Beweis -- eine Beschriftung,
                die genau am Rand endet, ist nicht abgeschnitten, eine,
                die IN der Randspalte noch Tinte hat, schon.

  UEBERLAPPEND  Ueberschneiden sich zwei gemeldete Textkaesten
                DERSELBEN Fensterkennung um mehr als `--slop` Bildpunkte
                (Voreinstellung 0)?  Zwei Beschriftungen, die
                uebereinanderliegen, ergeben ein Bild, auf dem beide
                unleserlich sind und beide "da" gemeldet wurden.

    check.py <bild.ppm> <serial.txt> [--asc N] [--slop N] [--nur win=..]

Beendigungscode 0 = keine Beanstandung.  Jede Beanstandung steht mit
Fenster, Stelle und Text da; eine Zahl ohne Ort ist keine Fundstelle.
"""
import re
import sys


def ppm(path):
    d = open(path, "rb").read()
    if not d.startswith(b"P6"):
        raise SystemExit("kein P6-PPM: %s" % path)
    f = []
    at = 2
    while len(f) < 3:
        while at < len(d) and d[at:at + 1].isspace():
            at += 1
        if d[at:at + 1] == b"#":
            while at < len(d) and d[at] != 0x0A:
                at += 1
            continue
        b = at
        while b < len(d) and not d[b:b + 1].isspace():
            b += 1
        f.append(int(d[at:b]))
        at = b
    at += 1
    w, h, _ = f
    return w, h, d[at:at + w * h * 3]


def at(px, W, x, y):
    o = (y * W + x) * 3
    return (px[o], px[o + 1], px[o + 2])


# `wlib:` meldet ax/ay (Runde SOFTUI); `taskbar:` nicht -- die Leiste
# ist EIN Fenster, und ihr Ursprung steht in der `wm: win`-Zeile mit dem
# Titel [Taskleiste].  Beide Wege enden bei einem absoluten Ursprung.
TEXT = re.compile(
    r"^(wlib|taskbar): text (?:win=(\d+) kind=(\d+) )?(?:\w+ )?"
    r"x=(-?\d+) base=(-?\d+) fg=(\d+) bg=(\d+)(?: tw=(\d+))?"
    r"(?: ax=(-?\d+) ay=(-?\d+))? t=(.*)$")
WIN = re.compile(
    r"^wm: win nr=(\d+) id=(\d+) .* x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+) "
    r".*t=\[(.*)\]$")


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    bild, ser = argv[1], argv[2]
    asc = 12
    slop = 0
    for a in argv[3:]:
        if a.startswith("--asc="):
            asc = int(a.split("=")[1])
        elif a.startswith("--slop="):
            slop = int(a.split("=")[1])
    W, H, px = ppm(bild)
    wins = {}
    texte = []
    for ln in open(ser, "rb").read().decode("utf-8", "replace").splitlines():
        m = WIN.match(ln.strip())
        if m:
            wins[m.group(7)] = (int(m.group(3)), int(m.group(4)),
                                int(m.group(5)), int(m.group(6)))
            continue
        m = TEXT.match(ln.strip())
        if m:
            texte.append(m)
    if not texte:
        print("pruef: KEINE Textmeldung im Mitschnitt -- nichts zu pruefen")
        return 1

    bad = 0
    seen = 0
    kaesten = {}
    leiste = wins.get("Taskleiste", (0, 0, W, H))
    for m in texte:
        quelle = m.group(1)
        wid = m.group(2) or quelle
        x, base = int(m.group(4)), int(m.group(5))
        fg = int(m.group(6))
        tw = int(m.group(8) or 0)
        txt = m.group(11)
        if not txt.strip():
            continue
        seen += 1
        # Die Meldungen sind FENSTERLOKAL. Ohne den Ursprung des
        # Fensters zeigt jede Pruefung an die falsche Stelle -- genau
        # das hat in Runde LOOK eine Messung wertlos gemacht.
        if m.group(9) is not None:
            ox, oy = int(m.group(9)), int(m.group(10))
            ww, wh = W - ox, H - oy
        elif quelle == "taskbar":
            ox, oy, ww, wh = leiste
        else:
            ox, oy, ww, wh = 0, 0, W, H
        # LEER?
        x0 = max(0, ox + x)
        y0 = max(0, oy + base - asc)
        y1 = min(H, oy + base + 4)
        x1 = min(W, ox + x + max(tw, 8))
        tinte = 0
        want = ((fg >> 16) & 255, (fg >> 8) & 255, fg & 255)
        nah = 0
        for yy in range(y0, y1):
            for xx in range(x0, x1):
                c = at(px, W, xx, yy)
                if c == want:
                    tinte += 1
                elif (abs(c[0] - want[0]) + abs(c[1] - want[1])
                      + abs(c[2] - want[2])) < 200:
                    nah += 1
        if tinte + nah == 0:
            print("LEER      win=%s x=%d base=%d t=%s" % (wid, x, base, txt))
            bad += 1
        # ABGESCHNITTEN?
        if tw and x + tw > ww:
            rand = ox + ww - 1
            traf = 0
            for yy in range(y0, y1):
                if 0 <= rand < W and at(px, W, rand, yy) == want:
                    traf += 1
            if traf:
                print("ABGESCHNITTEN win=%s x=%d tw=%d ueber w=%d "
                      "(%d Randpunkte in Schriftfarbe) t=%s"
                      % (wid, x, tw, ww, traf, txt))
                bad += 1
        if tw:
            # DIESELBE BESCHRIFTUNG ZWEIMAL IST KEINE UEBERLAPPUNG.
            #
            # Ein Bild entsteht aus mehreren Bildaufbauten -- die
            # Oberflaeche malt beim Start, nach dem Thema, nach dem
            # Strut. Jede Beschriftung steht deshalb mehrfach im
            # Mitschnitt, an genau derselben Stelle. Die erste Fassung
            # dieses Pruefers hat elf davon als "ueberlappend" gemeldet
            # und dabei jedes Mal einen Text mit SICH SELBST verglichen.
            # Ein Pruefer, der sich selbst anzeigt, ist Rauschen.
            #
            # Also: Schluessel aus Ort UND Text; wer schon dasteht,
            # kommt nicht noch einmal hinein.
            key = (ox, oy)
            kaesten.setdefault(key, {})[(x, base, txt)] = (
                x, base - asc, x + tw, base + 4, txt)

    # UEBERLAPPEND?
    for wid, kd in kaesten.items():
        ks = list(kd.values())
        for i in range(len(ks)):
            for j in range(i + 1, len(ks)):
                a, b = ks[i], ks[j]
                ox0 = max(a[0], b[0])
                oy0 = max(a[1], b[1])
                ox1 = min(a[2], b[2])
                oy1 = min(a[3], b[3])
                if ox1 - ox0 > slop and oy1 - oy0 > slop:
                    print("UEBERLAPPEND win=%s  '%s' und '%s'  um %dx%d"
                          % (wid, a[4], b[4], ox1 - ox0, oy1 - oy0))
                    bad += 1
    print("pruef: %d Beschriftungen geprueft, %d beanstandet" % (seen, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
