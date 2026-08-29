#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/softui/fokus.py -- WORAN MAN DAS SCHARFE FENSTER ERKENNT.

Die Runde nimmt der Titelleiste den Akzent.  Damit faellt der eine
Hinweis weg, an dem man bis jetzt gesehen hat, welches Fenster die
Tastatur bekommt -- und die Behauptung dieser Runde ist, dass der
SCHATTEN ihn ersetzt: das scharfe Fenster steht hoeher.

Das ist eine Behauptung ueber Bildpunkte und wird als solche geprueft.
Fuer jedes Fenster mit Schmuck aus dem Mitschnitt:

  tiefe    wie viele Helligkeitsstufen der dunkelste Schattenpunkt
           LINKS neben dem Fenster unter dem ungestoerten Untergrund
           liegt.  Links, weil dort nichts anderes hinreicht -- der
           Schatten sitzt einen Bildpunkt tiefer und die Zeile in der
           Mitte der Fensterhoehe trifft weder Titelleiste noch Griff.
  weite    wie viele Bildpunkte weit der Unterschied reicht.

Und zusaetzlich, weil es die andere Haelfte derselben Aussage ist:

  titel    ob die Titelleiste des scharfen Fensters gesaettigt ist.
           "kein akzent" heisst: die haeufigste Farbe des Balkens hat
           weniger als 40 Stufen Abstand zwischen ihrem groessten und
           ihrem kleinsten Kanal -- ein Grau, kein Blau.

    fokus.py <bild.ppm> <serial.txt>
"""
import re
import sys
from collections import Counter

BORDER = 2
TITLE_H = 22


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


WIN = re.compile(r"^wm: win nr=(\d+) id=(\d+) .*deco=(\d+) x=(-?\d+) "
                 r"y=(-?\d+) w=(\d+) h=(\d+) focus=(\d+) .*ow=(\d+) "
                 r"oh=(\d+) t=\[(.*)\]$")


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    W, H, px = ppm(argv[1])

    def at(x, y):
        o = (y * W + x) * 3
        return (px[o], px[o + 1], px[o + 2])

    # DER ABSTAND JE KANAL UND NICHT DER MITTELWERT.
    #
    # Der Mittelwert war die erste Fassung und sie hat im dunklen Schema
    # `tiefe=0` gemeldet, obwohl der Schatten da war: der Schreibtisch
    # ist dort (2, 6, 23) und der tiefste Schattenpunkt (2, 5, 17) --
    # ein Viertel des Blaukanals, und nach Division durch drei zwei
    # Stufen, die in der Rundung verschwinden. Ein Mass, das den
    # gesuchten Unterschied durch drei teilt, ist das falsche Mass.
    def abstand(a, b):
        return max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))

    wins = []
    for ln in open(argv[2], "rb").read().decode("utf-8", "replace").splitlines():
        m = WIN.match(ln.strip())
        if m and m.group(3) == "1":
            wins.append(dict(x=int(m.group(4)), y=int(m.group(5)),
                             fok=int(m.group(8)), ow=int(m.group(9)),
                             oh=int(m.group(10)), t=m.group(11)))
    if len(wins) < 2:
        print("weniger als zwei geschmueckte Fenster -- nichts zu vergleichen")
        return 1
    bad = 0
    for w in wins:
        x0 = w["x"]
        if x0 < 24:
            print("%s: zu nah am Rand, uebersprungen" % w["t"])
            continue
        # EINE ZEILE MIT RUHIGEM UNTERGRUND, und nicht einfach die
        # Mitte.  Die erste Fassung nahm die Mittelzeile und meldete
        # fuer das scharfe Fenster tiefe=0 -- links davon lag das ANDERE
        # Fenster, und die Stelle, an der sie den ungestoerten Grund
        # abgelesen hat, war dessen Beschriftung.  Also wird eine Zeile
        # gesucht, in der die acht Punkte 20 bis 13 links des Fensters
        # ALLE GLEICH sind; nur dort ist "der Grund" eine Zahl und keine
        # Vermutung.  Ueber alle solchen Zeilen wird der Median genommen.
        tiefen = []
        weiten = []
        gruende = []
        for y in range(w["y"] + w["oh"] // 4, w["y"] + w["oh"] * 3 // 4):
            if y < 0 or y >= H:
                continue
            probe = [at(x0 - k, y) for k in range(20, 12, -1)]
            if any(p != probe[0] for p in probe):
                continue
            grund = probe[0]
            t = 0
            wt = 0
            for k in range(1, 13):
                d = abstand(grund, at(x0 - k, y))
                if d > 1:
                    wt = max(wt, k)
                    t = max(t, d)
            tiefen.append(t)
            weiten.append(wt)
            gruende.append(grund)
        if not tiefen:
            print("%s: keine Zeile mit ruhigem Untergrund gefunden" % w["t"])
            bad += 1
            continue
        tiefen.sort()
        weiten.sort()
        tiefe = tiefen[len(tiefen) // 2]
        weite = weiten[len(weiten) // 2]
        grund = gruende[len(gruende) // 2]
        y = w["y"] + w["oh"] // 2
        art = "aktiv" if w["fok"] else "inaktiv"
        print("%s '%s' bei %d,%d: tiefe=%d weite=%d (grund "
              "#%02x%02x%02x, %d Zeilen)"
              % (art, w["t"], w["x"], w["y"], tiefe, weite, grund[0],
                 grund[1], grund[2], len(tiefen)))
        # Und der Balken.
        cnt = Counter()
        for j in range(w["y"] + BORDER, w["y"] + TITLE_H - 1):
            for i in range(w["x"] + BORDER, w["x"] + w["ow"] - BORDER):
                if 0 <= i < W and 0 <= j < H:
                    cnt[at(i, j)] += 1
        c, n = cnt.most_common(1)[0]
        spread = max(c) - min(c)
        if spread >= 40:
            print("titel: AKZENT -- '%s' #%02x%02x%02x, spanne %d"
                  % (w["t"], c[0], c[1], c[2], spread))
            bad += 1
        else:
            print("titel: kein akzent -- '%s' #%02x%02x%02x, spanne %d "
                  "auf %d punkten" % (w["t"], c[0], c[1], c[2], spread, n))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
