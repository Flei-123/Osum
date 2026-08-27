#!/usr/bin/env python3
"""tools/netview/kachel.py -- steht die Beschriftung, wo sie hingehoert?

Runde NETVIEW, dritter Nachtrag.

`schau.py` prueft, ob ein SYMBOL bildpunktgenau an einer Stelle steht.
Das genuegt fuer ein Zeichen und genuegt nicht fuer eine Kachel: eine
Kachel ist ein Rechteck mit zwei Textzeilen darin, und die beiden Fehler,
die eine Kachel wirklich hat, sieht kein Symbolvergleich --

  1. DIE BESCHRIFTUNG LAEUFT UEBER DEN RAND. Sie steht dann im
     Nachbarn oder auf dem Rahmen, und im Quelltext ist davon nichts zu
     sehen: dort steht `text_at(tx + 10, ...)` und das ist richtig.
  2. DIE ZWEI ZEILEN UEBERLAPPEN. Der Name der Kachel und das Wort
     darunter teilen sich eine Reihe Bildpunkte. Auch das steht in
     keiner Quelle -- es ist die Summe aus Kachelhoehe, Aufsteiger der
     Schrift und zwei Grundlinien, und die rechnet niemand im Kopf
     richtig.

BEIDE FEHLER HATTE DER ERSTE BAU DIESER RUNDE, und beide hat dieses
Werkzeug gefunden, nicht das Auge: "Netz vortaeuschen" ragte vier
Bildpunkte ueber die eigene Kachel hinaus, und auf der dritten Kachel
beruehrten sich die zwei Zeilen. Deshalb steht es hier und laeuft auf
allen vier Bildschirmraendern.

WIE GEMESSEN WIRD. Nicht gegen eine Sollfarbe, sondern gegen die
FLAECHE: alles, was nicht die Kachelfarbe und nicht die Rahmenfarbe ist,
ist Inhalt. Die Umrandung der Kachel wird ausgespart (zwei Bildpunkte
innen), damit der Rahmen selbst nicht als Beschriftung zaehlt.

DAS SYMBOLBAND WIRD AUSGESPART, und das ist keine Bequemlichkeit: die
Frage "kleben die Zeilen?" ist eine Frage nach den TEXTZEILEN. Die erste
Fassung fragte sie ueber die ganze Kachel und schlug bei `tile-hide` an,
dessen Zeichnung selbst aus zwei Teilen besteht -- ein Pfeil und eine
Linie darunter, mit einer leeren Reihe dazwischen. Das Werkzeug hatte
recht ueber die Bildpunkte und unrecht ueber die Frage. `oben` sagt ihm,
wie viele Reihen am oberen Rand der Kachel das Symbol einnimmt.

Verwendung:
    kachel.py <schirm.ppm> <panel-x> <panel-y> <panel-w> <panel-h>
              <pad> <tw> <th> <gap> <kacheln> <oben>
    -> "ok" und Rueckgabe 0, oder je Beanstandung eine Zeile und 1
"""

import sys


def ppm(pfad):
    d = open(pfad, "rb").read()
    if not d.startswith(b"P6"):
        raise SystemExit("kein P6-PPM: %s" % pfad)
    felder = []
    at = 2
    while len(felder) < 3:
        while at < len(d) and d[at:at + 1].isspace():
            at += 1
        if d[at:at + 1] == b"#":
            while d[at:at + 1] not in (b"\n", b""):
                at += 1
            continue
        anf = at
        while at < len(d) and not d[at:at + 1].isspace():
            at += 1
        felder.append(int(d[anf:at]))
    at += 1
    w, h, _ = felder
    return w, h, d[at:]


def main(argv):
    if len(argv) < 12:
        print(__doc__)
        return 2
    (schirm, px, py, pw, ph, pad, tw, th, gap, n, oben) = (
        argv[1], *[int(v) for v in argv[2:12]])
    w, h, roh = ppm(schirm)

    def pixel(x, y):
        if x < 0 or y < 0 or x >= w or y >= h:
            return None
        at = (y * w + x) * 3
        return (roh[at], roh[at + 1], roh[at + 2])

    fehler = []
    if px + pw > w or py + ph > h:
        print("das Panel bei %d,%d %dx%d liegt nicht auf einem %dx%d-Schirm"
              % (px, py, pw, ph, w, h))
        return 1

    for t in range(n):
        tx = px + pad + (t % 2) * (tw + gap)
        ty = py + pad + (t // 2) * (th + gap)
        # DIE FLAECHE DER KACHEL: die haeufigste Farbe im inneren
        # Rechteck. Nicht geraten und nicht aus einer Datei -- ein
        # Farbschema darf sich aendern, ohne dass diese Pruefung falsch
        # wird.
        zaehl = {}
        for y in range(ty + 3, ty + th - 3):
            for x in range(tx + 3, tx + tw - 3):
                c = pixel(x, y)
                zaehl[c] = zaehl.get(c, 0) + 1
        flaeche = max(zaehl, key=zaehl.get)

        # Alles, was nicht die Flaeche ist, ist Inhalt. Zeilenweise, weil
        # die Frage nach dem Ueberlappen eine Frage nach ZEILEN ist.
        # UEBER DIE GANZE KACHEL fuer die Frage nach dem Rand -- ein
        # Symbol, das ueberlaeuft, waere derselbe Fehler --, aber die
        # Bloecke werden erst UNTERHALB des Symbolbandes gezaehlt.
        zeilen = []
        rechts = tx + 2
        links = tx + tw - 3
        for y in range(ty + 2, ty + th - 2):
            n_in = 0
            for x in range(tx + 2, tx + tw - 3):
                if pixel(x, y) != flaeche:
                    n_in += 1
                    if x > rechts:
                        rechts = x
                    if x < links:
                        links = x
            zeilen.append((y, n_in))

        # UEBER DEN RAND: liegt rechts vom letzten eingefaerbten
        # Bildpunkt noch Kachel? Es muss, sonst steht die Beschriftung
        # auf dem Rahmen oder darueber hinaus.
        if rechts >= tx + tw - 4:
            fehler.append("Kachel %d: Inhalt bis x=%d, die Kachel endet "
                          "bei %d -- die Beschriftung laeuft ueber"
                          % (t, rechts, tx + tw - 1))
        if links <= tx + 2:
            fehler.append("Kachel %d: Inhalt ab x=%d, die Kachel faengt "
                          "bei %d an" % (t, links, tx))

        # ZWEI ZEILEN, EINE LUECKE. Die belegten Reihen in Bloecke
        # zerlegen; zwischen dem Block der Beschriftung und dem Block des
        # Wortes darunter muss mindestens eine leere Reihe liegen. Genau
        # eine waere zu wenig, um es "gestaltet" zu nennen, aber die
        # Pruefung fragt nur nach dem Fehler.
        bloecke = []
        anf = None
        for y, n_in in [(y, k) for (y, k) in zeilen if y >= ty + oben]:
            if n_in > 0 and anf is None:
                anf = y
            elif n_in == 0 and anf is not None:
                bloecke.append((anf, y - 1))
                anf = None
        if anf is not None:
            bloecke.append((anf, zeilen[-1][0]))
        if len(bloecke) != 2:
            fehler.append("Kachel %d: %d Textbloecke statt zwei "
                          "(Beschriftung, Wort) -- %s"
                          % (t, len(bloecke), bloecke))
        else:
            for i in range(len(bloecke) - 1):
                luecke = bloecke[i + 1][0] - bloecke[i][1] - 1
                if luecke < 2:
                    fehler.append("Kachel %d: nur %d Reihen zwischen %s "
                                  "und %s -- die Zeilen kleben"
                                  % (t, luecke, bloecke[i], bloecke[i + 1]))
        print("kachel %d: x %d..%d von %d..%d, Bloecke %s"
              % (t, links, rechts, tx, tx + tw - 1, bloecke))

    if fehler:
        for f in fehler:
            print("FALSCH " + f)
        return 1
    print("ok %d Kacheln, nichts laeuft ueber und nichts klebt" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
