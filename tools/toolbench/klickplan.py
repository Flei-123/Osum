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
    klickplan.py <serial.txt> navpage <n>       Mitte der Zeile n der Seitenleiste

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
CTXRECT = re.compile(r"taskmgr: ctxrect x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
TAB = re.compile(r"taskmgr: tabelle x=(\d+) y=(\d+) kopf=(\d+) zh=(\d+)")
NAV = re.compile(r"taskmgr: nav x=(\d+) y=(\d+) w=(\d+)")
COLUMN = re.compile(r"taskmgr: spalte c=(\d+) x=(\d+) w=(\d+)")
LINE = re.compile(r"taskmgr: zeile r=(\d+) pid=(\d+) ppid=(\d+) st=(\d+) "
                   r"pm=(\d+) kib=(\d+) kern=(\d+) ticks=(\d+) grp=(\d+) "
                   r"(uid=\d+ thr=\d+ prio=\d+ dr=\d+ dw=\d+ drate=\d+) "
                   r"(ntx=\d+ nrx=\d+|net=-) gpu=(\S+) y=(\d+) "
                   r"name=(.*)$")
DLGOK = re.compile(r"taskmgr: dialog ok x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
TBGEOM = re.compile(r"taskbar: geom edge=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
TBFELD = re.compile(r"taskbar: field net x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
QSOPEN = re.compile(r"qs: open x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
QSSYM = re.compile(r"qs: sym n=(\d+) x=(\d+) y=(\d+)")
QSKACHEL = re.compile(r"qs: kachel n=(\d+) platz=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
QSPLATTE = re.compile(r"qs: platte n=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
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


def last_block(zeilen):
    """Der letzte VOLLSTAENDIGE Block. Ein halb geschriebener Block am
    Ende des Mitschnitts (die Maschine wurde mittendrin abgeraeumt)
    haette Zeilen ohne Kopf."""
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
    if was in ("diskbtn", "diskrow", "disknav"):
        pat = {"diskbtn": r"disks: btn verb=(\S+) cx=(\d+) cy=(\d+)",
               "diskrow": r"disks: row p=(\d+) cx=(\d+) cy=(\d+)",
               "disknav": r"disks: navrow n=(\d+) cx=(\d+) cy=(\d+)"}[was]
        hit = None
        for z in zeilen:
            m = re.search(pat, z)
            if m and m.group(1) == argv[3]:
                hit = m
        if hit is None:
            raise SystemExit("klickplan: %s %s not reported" % (was, argv[3]))
        print("%s,%s" % (hit.group(2), hit.group(3)))
        return 0

    if was in ("qsfeld", "kachel", "qszeile1", "qszeile2"):
        cx = 0
        cy = 0
    else:
        x, y, w, h, cx, cy = fenster(zeilen)

    if was == "qsfeld":
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
        t = argv[3]
        o = None
        k = None
        for z in zeilen:
            m = QSOPEN.search(z)
            if m:
                o = m
            m = QSKACHEL.search(z)
            if m and m.group(1) == t:
                k = m
            m = QSPLATTE.search(z)
            if m and m.group(1) == t:
                k = m
        if o is None or k is None:
            raise SystemExit("klickplan: Kachel %s nicht gemeldet" % t)
        ox, oy = int(o.group(1)), int(o.group(2))
        print("%d,%d" % (ox + int(k.group(2)) + int(k.group(4)) // 2,
                         oy + int(k.group(3)) + int(k.group(5)) // 2))
        return 0

    if was in ("qszeile1", "qszeile2"):
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
        d = None
        for z in zeilen:
            m = DLGOK.search(z)
            if m:
                d = m
        if d is None:
            raise SystemExit("klickplan: kein Ja-Knopf im Mitschnitt")
        dx, dy, dw, dh = (int(v) for v in d.groups())
        print("%d,%d" % (cx + dx + dw // 2, cy + dy + dh // 2))
        return 0

    if was == "suche":
        r = None
        for z in zeilen:
            m = RECT.search(z)
            if m and m.group(1) == "7":
                r = m
        if r is None:
            raise SystemExit("klickplan: no search entry in the capture")
        bx = int(r.group(3)) + int(r.group(5)) // 2
        by = int(r.group(4)) + int(r.group(6)) // 2
        print("%d,%d" % (cx + bx, cy + by))
        return 0

    if was == "navpage":
        r = None
        for z in zeilen:
            m = NAV.search(z)
            if m and r is None:
                r = m
        if r is None:
            raise SystemExit("klickplan: no navigation line in the capture")
        bx = int(r.group(1)) + int(r.group(3)) // 2
        by = int(r.group(2)) + 40 * int(argv[3]) + 20
        print("%d,%d" % (cx + bx, cy + by))
        return 0

    if was == "restile":
        want = str(20 + int(argv[3]))
        r = None
        for z in zeilen:
            m = RECT.search(z)
            if m and m.group(1) == want:
                r = m
        if r is None:
            raise SystemExit("klickplan: resource tile %s not in the capture" % argv[3])
        bx = int(r.group(3)) + int(r.group(5)) // 2
        by = int(r.group(4)) + int(r.group(6)) // 2
        print("%d,%d" % (cx + bx, cy + by))
        return 0

    if was == "ctxbox":
        c = None
        for z in zeilen:
            m = CTXRECT.search(z)
            if m:
                c = m
        if c is None:
            raise SystemExit("klickplan: no context menu in the capture")
        mx, my, mw, mh = (int(v) for v in c.groups())
        print("%d,%d,%d,%d" % (cx + mx, cy + my, mw, mh))
        return 0

    if was == "ctxzeile":
        c = None
        for z in zeilen:
            m = CTXRECT.search(z)
            if m:
                c = m
        if c is None:
            raise SystemExit("klickplan: no context menu in the capture")
        n = int(argv[3])
        mx, my, mw, mh = (int(v) for v in c.groups())
        rows = max(1, (mh - 8) // 28)
        print("%d,%d" % (cx + mx + mw // 2, cy + my + 4 + 28 * (n - 1) + 14))
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
            m = COLUMN.search(z)
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
        block = last_block(zeilen)
        treffer = None
        for z in block:
            m = LINE.search(z)
            if not m:
                continue
            if was == "pid" and m.group(2) == ziel:
                treffer = m
            if was in ("zeile", "pidvon") and m.group(14).strip() == ziel:
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
        ry = int(treffer.group(13)) + zh // 2
        rx = int(t.group(1)) + 40
        print("%d,%d" % (cx + rx, cy + ry))
        return 0

    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
