#!/usr/bin/env python3
"""tools/speicher/kachelprobe.py -- die Treemap NACHMESSEN, im Bild.

Runde SPEICHER. `/bin/speicher` meldet ueber die serielle Leitung, welche
Kachel es wohin und wie breit gemalt hat. Das ist die Rechnung des
Programms ueber sich selbst, und sie beweist nichts: ein Programm, das
die Flaechen falsch aufteilt, meldet die falschen Flaechen genauso
zuversichtlich. Die Lehre aus Runde K7B steht im Laeufer von K15 und
gilt hier wieder -- gemessen wird im BILD.

WAS DIESE DATEI TUT:

  1. Sie sucht den EINEN Versatz, mit dem ALLE gemeldeten Kacheln im Bild
     ihre gemeldete Farbe haben. Ein Versatz, der nur fuer die Haelfte
     passt, ist kein Versatz, sondern Zufall -- Kacheln sind gross, und
     ein danebenliegender Griff trifft leicht die Nachbarkachel.
  2. Sie misst die BREITE JEDER KACHEL AM BILD: wie viele Bildpunkte in
     einer Reihe hintereinander diese Farbe tragen. Das ist die
     eigentliche Zusage der Darstellung -- die Flaeche soll dem Anteil
     entsprechen. Meldete das Programm 130 und malte 40, faende Punkt 1
     die Kachel trotzdem.
  3. Sie prueft, dass die Breiten in derselben REIHENFOLGE fallen wie die
     Anteile. Eine Treemap, in der die kleinste Kachel die groesste ist,
     ist schlimmer als gar keine.

    kachelprobe.py <bild.ppm> <serielle-ausgabe>
"""

import re
import sys

KACHEL = re.compile(
    r"speicher: kachel i=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+) "
    r"farbe=(\d+) name=(\S+)")

# Die Kachelkoordinaten sind FENSTERrelativ. Das Fenster steht bei 40,40,
# und darauf kommen Rahmen und Titelleiste -- welche genau, sagt die
# Bibliothek, nicht diese Datei. Also werden die plausiblen Versaetze
# durchprobiert und der eine genommen, mit dem ALLES passt.
VERSAETZE = [(x, y) for x in (40, 41, 42, 43) for y in
             (40, 42, 60, 61, 62, 63, 64, 65, 66)]


def ppm(pfad):
    with open(pfad, "rb") as f:
        roh = f.read()
    if not roh.startswith(b"P6"):
        raise SystemExit("kachelprobe: kein P6-PPM")
    at, felder = 2, []
    while len(felder) < 3:
        while roh[at:at + 1].isspace():
            at += 1
        if roh[at:at + 1] == b"#":
            while roh[at:at + 1] != b"\n":
                at += 1
            continue
        a = at
        while not roh[at:at + 1].isspace():
            at += 1
        felder.append(int(roh[a:at]))
    at += 1
    return felder[0], felder[1], roh[at:]


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    W, H, px = ppm(argv[1])
    txt = open(argv[2], "rb").read().decode("latin-1")

    def farbe(x, y):
        if x < 0 or y < 0 or x >= W or y >= H:
            return -1
        o = (y * W + x) * 3
        return (px[o] << 16) | (px[o + 1] << 8) | px[o + 2]

    kacheln = [(int(m.group(1)), int(m.group(2)), int(m.group(3)),
                int(m.group(4)), int(m.group(5)), int(m.group(6)),
                m.group(7)) for m in KACHEL.finditer(txt)]
    if not kacheln:
        print("kachelprobe: keine einzige Kachel gemeldet")
        return 1

    treffer = None
    for ox, oy in VERSAETZE:
        if all(farbe(x + w // 2 + ox, y + h // 2 + oy) == f
               for _i, x, y, w, h, f, _n in kacheln):
            treffer = (ox, oy)
            break
    if treffer is None:
        print("kachelprobe: KEIN Versatz, bei dem alle %d Kacheln ihre "
              "Farbe haben" % len(kacheln))
        for _i, x, y, w, h, f, n in kacheln:
            print("  %-10s gemeldet %06X, im Bild %06X"
                  % (n, f, farbe(x + w // 2 + 42, y + h // 2 + 62)))
        return 1
    ox, oy = treffer
    print("kachelprobe: %d Kacheln, Versatz des Fensterinhalts %d,%d"
          % (len(kacheln), ox, oy))

    schlecht = 0
    breiten = []
    for _i, x, y, w, h, f, n in kacheln:
        yy = y + h // 2 + oy
        # Von der Mitte nach links und rechts, solange die Farbe haelt.
        mitte = x + w // 2 + ox
        li = mitte
        while farbe(li - 1, yy) == f:
            li -= 1
        re_ = mitte
        while farbe(re_ + 1, yy) == f:
            re_ += 1
        gemessen = re_ - li + 1
        breiten.append((n, w, gemessen))
        # Ein Rahmen um die Kachel darf ein paar Punkte kosten.
        gut = abs(gemessen - w) <= 4
        if not gut:
            schlecht += 1
        print("  %-10s gemeldet w=%-5d im Bild %-5d %s"
              % (n, w, gemessen, "" if gut else "<-- ABWEICHUNG"))

    fallend = all(breiten[k][2] >= breiten[k + 1][2] - 4
                  for k in range(len(breiten) - 1))
    print("kachelprobe: die Breiten fallen mit dem Anteil: %s"
          % ("ja" if fallend else "NEIN"))
    if schlecht or not fallend:
        print("kachelprobe: %d Kacheln stimmen nicht" % schlecht)
        return 1
    print("kachelprobe: alle Kacheln haben im Bild die Breite, die das "
          "Programm gemeldet hat")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
