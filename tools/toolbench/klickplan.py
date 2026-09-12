#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/toolbench/klickplan.py -- WOHIN KLICKEN, AUS DEM MITSCHNITT.

    klickplan.py <serial.txt> zeile <name>      Mitte der Zeile mit diesem
                                                Programmnamen
    klickplan.py <serial.txt> pid <n>           dasselbe ueber die PID
    klickplan.py <serial.txt> spalte <c>        Mitte des Kopffeldes einer Spalte
    klickplan.py <serial.txt> knopf             Mitte des Knopfes "beenden"
    klickplan.py <serial.txt> ja                Mitte des Ja-Knopfes des Dialogs
    klickplan.py <serial.txt> pidvon <name>     nur die PID ausgeben

Es gibt hier KEINE Anordnung. Jede Zahl steht im Mitschnitt, weil das
Programm sie gemeldet hat:

    wlib: win id=.. x=.. y=.. cx=.. cy=..    wo die Arbeitsflaeche liegt
    taskmgr: rect id=6 kind=2 x=.. y=.. ..   der Knopf
    taskmgr: tabelle x=.. y=.. kopf=.. zh=.. die Tabelle
    taskmgr: spalte c=.. x=.. w=..           ein Kopffeld
    taskmgr: zeile r=.. pid=.. y=.. name=..  eine Zeile

Ein Laeufer, der die Zeilenhoehe selbst ausrechnete, pruefte damit
seinen eigenen Nachbau der Anordnung. Diese Datei rechnet nur EINES:
Fensterkoordinate plus Ursprung der Arbeitsflaeche.
"""
import re
import sys

WIN = re.compile(r"wlib: win id=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+) "
                 r"cx=(\d+) cy=(\d+)")
RECT = re.compile(r"taskmgr: rect id=(\d+) kind=(\d+) x=(\d+) y=(\d+) "
                  r"w=(\d+) h=(\d+)")
TAB = re.compile(r"taskmgr: tabelle x=(\d+) y=(\d+) kopf=(\d+) zh=(\d+)")
SPALTE = re.compile(r"taskmgr: spalte c=(\d+) x=(\d+) w=(\d+)")
ZEILE = re.compile(r"taskmgr: zeile r=(\d+) pid=(\d+) ppid=(\d+) st=(\d+) "
                   r"pm=(\d+) kib=(\d+) kern=(\d+) ticks=(\d+) y=(\d+) "
                   r"name=(.*)$")
# Die Spur der Bibliothek traegt seit Runde SOFTUI zwei Felder mehr
# (`ax=`, `ay=`, der Ursprung der Arbeitsflaeche). Wer sie nicht
# zulaesst, findet den Ja-Knopf nicht -- und es sieht aus, als haette
# die Nachfrage keinen.
TBGEOM = re.compile(r"taskbar: geom edge=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
TBFELD = re.compile(r"taskbar: field net x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
QSOPEN = re.compile(r"qs: open x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
QSSYM = re.compile(r"qs: sym n=(\d+) x=(\d+) y=(\d+)")
DLG = re.compile(r"wlib: text win=(\d+) kind=2 x=(\d+) base=(\d+) fg=(\d+) "
                 r"bg=(\d+) tw=(\d+)(?: ax=\d+ ay=\d+)? t=(.*)$")


def lies(pfad):
    return open(pfad, "rb").read().decode("latin1").splitlines()


def fenster(zeilen, welches=0):
    """Das Fenster des Aufgabenverwalters: das GROESSTE, das gemeldet
    wurde -- der Dialog ist 340 breit, das Hauptfenster 752. Bei
    `welches=1` das KLEINSTE, also der Dialog."""
    ws = {}
    for z in zeilen:
        m = WIN.search(z)
        if m:
            ws[m.group(1)] = tuple(int(v) for v in m.groups()[1:])
    if not ws:
        raise SystemExit("klickplan: keine 'wlib: win'-Zeile im Mitschnitt")
    v = sorted(ws.values(), key=lambda t: t[2] * t[3])
    return v[0] if welches else v[-1]


def letzter_block(zeilen):
    """Der letzte VOLLSTAENDIGE Block. Ein halb geschriebener Block am
    Ende des Mitschnitts (die Maschine wurde mittendrin abgeraeumt)
    haette Zeilen ohne Kopf."""
    # UND NUR BLOECKE NACH DER LETZTEN SORTIERUNG. Ein Klick in die
    # Kopfzeile stellt die Liste um; ein Block von davor beschreibt eine
    # Reihenfolge, die es nicht mehr gibt, und die Zeile darunter gehoert
    # dann einem anderen Prozess. GEMESSEN: der Laeufer waehlte den
    # Schreibtisch statt des Starters, weil er eine Zeile zu tief traf.
    ab = 0
    for i, z in enumerate(zeilen):
        if "taskmgr: sortiert " in z:
            ab = i
    zeilen = zeilen[ab:]
    anf = None
    ende = None
    for i, z in enumerate(zeilen):
        if z.startswith("taskmgr: blockende "):
            ende = i
    if ende is None:
        return zeilen
    for i in range(ende, -1, -1):
        if zeilen[i].startswith("taskmgr: block "):
            anf = i
            break
    return zeilen[anf:ende + 1] if anf is not None else zeilen


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    zeilen = lies(argv[1])
    was = argv[2]
    # DAS FENSTER WIRD ERST GEHOLT, WENN ES GEBRAUCHT WIRD. Die Ziele des
    # Kontrollzentrums liegen in der Taskleiste und im Panel -- beides
    # sind Fenster, die keine Widget-Spur schreiben, und ein Laeufer, der
    # hier abbricht, weil ein UNBETEILIGTES Fenster fehlt, misst nichts.
    if was in ("qsfeld", "kachel", "qszeile1", "qszeile2"):
        cx = 0
        cy = 0
    else:
        x, y, w, h, cx, cy = fenster(zeilen)

    if was == "qsfeld":
        # Die Ecke der Taskleiste, in der die Symbole stehen -- ein Klick
        # dorthin oeffnet die Schnelleinstellungen (Runde NETVIEW,
        # dritter Nachtrag). Die Leiste meldet beides: wo SIE steht und
        # wo das Feld IN ihr liegt.
        g = None
        f = None
        for z in zeilen:
            m = TBGEOM.search(z)
            if m:
                g = m
            m = TBFELD.search(z)
            if m:
                f = m
        if g is None or f is None:
            raise SystemExit("klickplan: die Leiste hat ihr Netzfeld nicht gemeldet")
        fx = int(g.group(2)) + int(f.group(1)) + int(f.group(3)) // 2
        fy = int(g.group(3)) + int(f.group(2)) + int(f.group(4)) // 2
        print("%d,%d" % (fx, fy))
        return 0

    if was == "kachel":
        # Eine Kachel des Kontrollzentrums. Das Panel meldet die Stelle
        # JEDES Symbols in SCHIRMKOORDINATEN; die Kachel ist 180 x 74
        # gross und ihr Symbol sitzt 10 Bildpunkte vom Rand.
        t = argv[3]
        s_ = None
        for z in zeilen:
            m = QSSYM.search(z)
            if m and m.group(1) == t:
                s_ = m
        if s_ is None:
            raise SystemExit("klickplan: Kachel %s nicht gemeldet" % t)
        print("%d,%d" % (int(s_.group(2)) - 10 + 90, int(s_.group(3)) - 10 + 37))
        return 0

    if was in ("qszeile1", "qszeile2"):
        # Die zwei Verknuepfungszeilen am Fuss des Panels. Ihre Lage
        # steht im Quelltext von qs.fi als L1Y/L2Y; hier wird sie aus dem
        # gemeldeten Panelrechteck und der Hoehe zurueckgerechnet -- die
        # Zeilen sind die letzten beiden, je 22 hoch, mit 8 Abstand und
        # 10 Rand darunter.
        o = None
        for z in zeilen:
            m = QSOPEN.search(z)
            if m:
                o = m
        if o is None:
            raise SystemExit("klickplan: das Panel hat sich nicht gemeldet")
        px_, py_, pw, ph = (int(v) for v in o.groups())
        l2 = py_ + ph - 10 - 22
        l1 = l2 - 8 - 22
        y = l1 if was == "qszeile1" else l2
        print("%d,%d" % (px_ + 60, y + 11))
        return 0

    if was == "ja":
        # Der Dialog ist ein eigenes Fenster; sein Ja-Knopf ist der
        # erste Knopftext darin. `wlib` meldet ihn mit seiner Stelle und
        # seiner Breite.
        dx, dy, dw, dh, dcx, dcy = fenster(zeilen, 1)
        best = None
        for z in zeilen:
            m = DLG.search(z)
            if m and m.group(7).strip() in ("Ja", "Yes", "OK"):
                best = m
        if best is None:
            raise SystemExit("klickplan: kein Ja-Knopf im Mitschnitt")
        bx = int(best.group(2)) + int(best.group(6)) // 2
        by = int(best.group(3)) - 5
        print("%d,%d" % (dcx + bx, dcy + by))
        return 0

    if was == "knopf":
        r = None
        for z in zeilen:
            m = RECT.search(z)
            if m and m.group(2) == "2":
                r = m
        if r is None:
            raise SystemExit("klickplan: kein Knopf im Mitschnitt")
        bx = int(r.group(3)) + int(r.group(5)) // 2
        by = int(r.group(4)) + int(r.group(6)) // 2
        print("%d,%d" % (cx + bx, cy + by))
        return 0

    if was == "spalte":
        c = argv[3]
        s = None
        for z in zeilen:
            m = SPALTE.search(z)
            if m and m.group(1) == c:
                s = m
        if s is None:
            raise SystemExit("klickplan: Spalte %s nicht gemeldet" % c)
        t = None
        for z in zeilen:
            m = TAB.search(z)
            if m:
                t = m
        sx = int(s.group(2)) + int(s.group(3)) // 2
        sy = int(t.group(2)) + int(t.group(4)) // 2 + 2
        print("%d,%d" % (cx + sx, cy + sy))
        return 0

    if was in ("zeile", "pid", "pidvon"):
        ziel = argv[3]
        block = letzter_block(zeilen)
        treffer = None
        for z in block:
            m = ZEILE.search(z)
            if not m:
                continue
            if was == "pid" and m.group(2) == ziel:
                treffer = m
            if was in ("zeile", "pidvon") and m.group(10).strip() == ziel:
                treffer = m
        if treffer is None:
            raise SystemExit("klickplan: '%s' steht nicht in der Liste" % ziel)
        if was == "pidvon":
            print(treffer.group(2))
            return 0
        t = None
        for z in zeilen:
            m = TAB.search(z)
            if m:
                t = m
        zh = int(t.group(4))
        ry = int(treffer.group(9)) + zh // 2
        rx = int(t.group(1)) + 40
        print("%d,%d" % (cx + rx, cy + ry))
        return 0

    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
