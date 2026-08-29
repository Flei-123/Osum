#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/supersearch/messen.py -- EIN BILDSCHIRMFOTO WIRD GEMESSEN UND
NICHT ANGESEHEN.

    messen.py zeilen  <ppm> <serial.txt>
    messen.py ecke    <ppm> <serial.txt>
    messen.py schatten <mit.ppm> <ohne.ppm> <serial.txt>
    messen.py feld    <ppm> <serial.txt>

WARUM DAS HIER STEHT. In diesem Baum ist schon einmal genau der Fehler
passiert, den ein Blick auf ein Bild nicht findet: JEDER FENSTERTITEL WAR
LEER, weil `title_text` zweimal durch WM_OFF gelesen hat. Das Fenster
stand, der Rahmen stimmte, die Farben stimmten -- und auf der Titelleiste
war nichts. Wer das Bild ansieht, sagt "sieht gut aus"; wer die
Tintenpunkte zaehlt, sagt "0 von 1400".

Also wird gezaehlt. Und zwar an den Stellen, die das Programm SELBST auf
der seriellen Leitung genannt hat -- ein Fenster, das eine Stelle meldet
und an einer anderen malt, faellt hier durch, und das ist der halbe Sinn
der Sache.

DIE GRUNDFARBE WIRD NICHT ANGENOMMEN, sondern gemessen: die haeufigste
Farbe im Kaestchen ist der Grund, alles andere ist Tinte. Damit geht der
Pruefer in jedem Farbschema, hell wie dunkel.
"""
import re
import sys
from collections import Counter


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
            while d[at:at + 1] not in (b"\n", b""):
                at += 1
            continue
        a = at
        while at < len(d) and not d[at:at + 1].isspace():
            at += 1
        f.append(int(d[a:at]))
    at += 1
    return f[0], f[1], d[at:]


def px(w, h, data, x, y):
    if x < 0 or y < 0 or x >= w or y >= h:
        return None
    o = (y * w + x) * 3
    return (data[o], data[o + 1], data[o + 2])


def kasten(w, h, data, x0, y0, x1, y1):
    """Tinte in einem Kaestchen: die haeufigste Farbe ist der Grund."""
    c = Counter()
    for y in range(max(0, y0), min(h, y1)):
        for x in range(max(0, x0), min(w, x1)):
            c[px(w, h, data, x, y)] += 1
    if not c:
        return 0, 0, None
    grund, _n = c.most_common(1)[0]
    tinte = sum(v for k, v in c.items() if k != grund)
    return tinte, sum(c.values()), grund


def offen(log):
    """Die letzte Zeile `sucher: open ...` -- wo das Fenster steht."""
    letzte = None
    for z in open(log, "rb").read().decode("utf-8", "replace").splitlines():
        if z.startswith("sucher: open "):
            letzte = z
    if letzte is None:
        raise SystemExit("keine Zeile 'sucher: open' in %s" % log)
    g = dict(re.findall(r"(\w+)=(\d+)", letzte))
    return int(g["x"]), int(g["y"]), int(g["w"]), int(g["h"])


def zeilen_aus(log):
    """Die Zeilen der LETZTEN Trefferliste -- und nur die.

    DIE ERSTE FASSUNG SAMMELTE UEBER DEN GANZEN LAUF, und das ist der
    Fehler, den die Runde LOOK schon einmal aufgeschrieben hat: eine
    Messung muss den Zustand ZUM ZEITPUNKT DES FOTOS nehmen, nicht den
    letzten, den es je gab.  Gemessen: die Eingabe "g" gab acht Treffer,
    die Eingabe "gro" danach zwei -- und der Pruefer suchte im Bild nach
    acht Beschriftungen, fand sechs leere Kaesten und meldete zwoelf
    Fehler an einem Fenster, das genau richtig gemalt hatte.

    Jede Zeile `sucher: query` faengt eine neue Liste an; also wird bei
    jeder von ihnen zurueckgesetzt.
    """
    aus = {}
    for z in open(log, "rb").read().decode("utf-8", "replace").splitlines():
        if z.startswith("sucher: query "):
            aus = {}
        m = re.match(r"sucher: zeile n=(\d+) src=(\d+) rk=(\d+) x=(\d+) "
                     r"base=(\d+) ix=(\d+) iy=(\d+) sel=(\d+) "
                     r"txt=\[(.*)\] sub=\[(.*)\]$", z)
        if m:
            aus[int(m.group(1))] = {
                "n": int(m.group(1)), "src": int(m.group(2)),
                "rk": int(m.group(3)), "x": int(m.group(4)),
                "base": int(m.group(5)), "ix": int(m.group(6)),
                "iy": int(m.group(7)), "sel": int(m.group(8)),
                "txt": m.group(9), "sub": m.group(10)}
    return [aus[k] for k in sorted(aus)]


def cmd_zeilen(argv):
    w, h, d = ppm(argv[0])
    zs = zeilen_aus(argv[1])
    if not zs:
        print("keine gemeldete Zeile")
        return 1
    schlecht = 0
    for z in zs:
        # Das Kaestchen der Beschriftung: von der gemeldeten Stelle bis
        # 300 Bildpunkte weiter, und ueber der Grundlinie so hoch wie
        # eine Zeile. Die Grundlinie ist die UNTERKANTE der Buchstaben
        # ohne Unterlaenge, also liegt die Tinte darueber.
        t, ges, grund = kasten(w, h, d, z["x"], z["base"] - 13,
                               z["x"] + 300, z["base"] + 4)
        ti, gi, _gr = kasten(w, h, d, z["ix"], z["iy"],
                             z["ix"] + 16, z["iy"] + 16)
        soll = len(z["txt"].strip())
        marke = "OK "
        if soll > 0 and t == 0:
            marke = "LEER"
            schlecht += 1
        elif soll > 0 and t < soll * 3:
            # Ein Buchstabe dieser Schrift hat mindestens drei
            # eingefaerbte Bildpunkte. Weniger heisst: da steht etwas
            # anderes als der gemeldete Text.
            marke = "DUENN"
            schlecht += 1
        if ti == 0:
            marke = marke + "+KEINSYMBOL"
            schlecht += 1
        print("%s zeile %d src=%d rk=%d tinte=%d von %d  symbol=%d von %d  "
              "zeichen=%d  txt=[%s]"
              % (marke, z["n"], z["src"], z["rk"], t, ges, ti, gi, soll,
                 z["txt"]))
    print("zeilen: %d geprueft, %d schlecht" % (len(zs), schlecht))
    return 1 if schlecht else 0


def cmd_feld(argv):
    """Das Eingabefeld: steht darin Tinte, und ist der Balken da?"""
    w, h, d = ppm(argv[0])
    x, y, ww, hh = offen(argv[1])
    PAD, EH = 16, 36
    t, ges, grund = kasten(w, h, d, x + PAD, y + PAD,
                           x + ww - PAD, y + PAD + EH)
    print("feld: tinte=%d von %d grund=%s" % (t, ges, grund))
    return 0 if t > 0 else 1


def cmd_ecke(argv):
    """DIE RUNDE ECKE. Der aeusserste Bildpunkt des Fensterrechtecks darf
    NICHT die Fensterfarbe tragen -- dort liegt der Schreibtisch, und
    genau das ist der Unterschied zwischen einer runden und einer eckigen
    Ecke. Die Mitte einer Kante muss sie dagegen tragen."""
    w, h, d = ppm(argv[0])
    x, y, ww, hh = offen(argv[1])
    innen, _n, grund = kasten(w, h, d, x + ww // 2 - 20, y + hh // 2 - 20,
                              x + ww // 2 + 20, y + hh // 2 + 20)
    kante = px(w, h, d, x + ww // 2, y)
    schlecht = 0
    # WAS "ECKIG" HEISST, und warum es nicht "gleich dem Fenstergrund"
    # heissen darf: ein Fenster mit Rahmen traegt an seiner Oberkante
    # NICHT die Fuellfarbe, sondern die Rahmenfarbe. Der Satz `classic`
    # hat radius_window=0 und einen Rahmen -- seine Ecken sind
    # kerzengerade und trugen (226,232,240), also nicht den Grund
    # (255,255,255); die alte Regel nannte sie deshalb "rund" und die
    # Gegenprobe scheiterte, obwohl das Bild genau das zeigte, was es
    # zeigen sollte.
    #
    # Die Kantenmitte oben ist per Bauart ein Punkt, der ZUM FENSTER
    # gehoert -- Rahmen oder Fuellung, je nach Satz. Eine Ecke ist
    # eckig, wenn sie dasselbe traegt wie diese Kante oder wie der
    # Fenstergrund; sie ist rund, wenn dort etwas anderes liegt, denn
    # dann sieht man an dieser Stelle den Schreibtisch.
    for nx, ny, wie in ((x, y, "oben links"), (x + ww - 1, y, "oben rechts"),
                        (x, y + hh - 1, "unten links"),
                        (x + ww - 1, y + hh - 1, "unten rechts")):
        p = px(w, h, d, nx, ny)
        gleich = (p == grund) or (p == kante)
        print("ecke %-13s (%d,%d) = %s  %s" %
              (wie, nx, ny, p, "ECKIG" if gleich else "rund"))
        if gleich:
            schlecht += 1
    print("kantenmitte oben (%d,%d) = %s (Fenstergrund %s)"
          % (x + ww // 2, y, kante, grund))
    print("ecke: %d von 4 Ecken sind eckig" % schlecht)
    return 1 if schlecht else 0


def cmd_schatten(argv):
    """DER SCHATTEN. Er faellt AUSSERHALB des Fensters, also wird ein
    Streifen daneben mit demselben Streifen aus einem Lauf OHNE das
    Fenster verglichen. Dunkler heisst Schatten; gleich heisst keiner."""
    w, h, d = ppm(argv[0])
    w2, h2, d2 = ppm(argv[1])
    x, y, ww, hh = offen(argv[2])
    if (w, h) != (w2, h2):
        print("die beiden Bilder sind verschieden gross")
        return 1
    dunkler = 0
    gleich = 0
    heller = 0
    for dy in range(0, hh):
        for dx in range(1, 7):
            a = px(w, h, d, x + ww - 1 + dx, y + dy)
            b = px(w2, h2, d2, x + ww - 1 + dx, y + dy)
            if a is None or b is None:
                continue
            sa, sb = sum(a), sum(b)
            if sa < sb - 4:
                dunkler += 1
            elif sa > sb + 4:
                heller += 1
            else:
                gleich += 1
    print("schatten rechts: %d dunkler, %d gleich, %d heller"
          % (dunkler, gleich, heller))
    return 0 if dunkler > 0 else 1


def main(a):
    if len(a) < 2:
        print(__doc__)
        return 2
    f = {"zeilen": cmd_zeilen, "feld": cmd_feld, "ecke": cmd_ecke,
         "schatten": cmd_schatten}.get(a[0])
    if f is None:
        print(__doc__)
        return 2
    return f(a[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
