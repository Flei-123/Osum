#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""appprobe.py -- LASSEN SICH DIE PROGRAMME STARTEN? Und danach: geht Alt+Tab?

    python3 appprobe.py [name] [breite] [hoehe]

Das ist der Kern der ganzen Runde. DURCHKLICK hat gemessen, dass jeder
Programmstart mit `pid=-22` endet (SYS_SPAWN mit einem Pfad statt einer
Nummer); TUERSCHLOSS 1/n hat die vier vergessenen Aufrufer auf SYS_EXEC
umgestellt. Hier wird nachgesehen, ob das auf dem fertigen Stick wirkt.

WO GEKLICKT WIRD, UND WARUM NICHT GERATEN. Alle Zahlen kommen aus der
seriellen Leitung desselben Laufes:

    wm: fen ... id=11 x=8 y=452 w=440 h=300 lay=2   das Menuefenster
    launcher: rect id=2 kind=5 x=12 y=84 w=416 h=168   die Liste darin
    launcher: rows x=40 base=99 zh=20                  Zeilenhoehe 20

Der Klick auf Eintrag i geht also auf
    (8 + 12 + 60,  452 + 84 + 10 + i*20).
`launcher: rows base=` ist die GRUNDLINIE der ersten Zeile im
Fensterkoordinatensystem -- die Mitte der Zeile liegt darueber, deshalb
wird von `rect id=2` aus gerechnet und nicht von `base`.
"""
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
from klick import Maschine

NAME = sys.argv[1] if len(sys.argv) > 1 else "app"
BREITE = int(sys.argv[2]) if len(sys.argv) > 2 else 1280
HOEHE = int(sys.argv[3]) if len(sys.argv) > 3 else 800
D = os.path.join(HIER, "laeufe", NAME)
SHOTS = os.path.join(HIER, "shots", NAME)
os.makedirs(SHOTS, exist_ok=True)
SER = os.path.join(D, "serial.txt")


def s():
    try:
        return open(SER, "rb").read().replace(b"\x00", b"").decode(
            "utf-8", "replace")
    except OSError:
        return ""


def menue_lage(t):
    """(mx, my, lx, ly, zh) -- alles aus der Leitung, nichts geraten."""
    f = re.findall(r"wm: fen i=\d+ id=\d+ x=(\d+) y=(\d+) w=440 h=300 lay=2", t)
    r = re.findall(r"launcher: rect id=2 kind=5 x=(\d+) y=(\d+) "
                   r"w=(\d+) h=(\d+)", t)
    z = re.findall(r"launcher: rows x=\d+ base=\d+ zh=(\d+)", t)
    if not f or not r:
        return None
    return (int(f[-1][0]), int(f[-1][1]), int(r[-1][0]), int(r[-1][1]),
            int(z[-1]) if z else 20)


def offen(t):
    """Die Fenster, zwischen denen ein Mensch wechseln kann."""
    return sorted(set(re.findall(
        r"wm: fen i=\d+ id=(\d+) [^\n]*lay=1 fl=0", t)))


def main():
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(BREITE), str(HOEHE)], check=True,
                   capture_output=True, text=True, timeout=60)
    t0 = time.time()
    while time.time() - t0 < 150:
        if "taskbar: start x=" in s():
            break
        time.sleep(0.3)
    print("hochgefahren nach %.1f s" % (time.time() - t0), flush=True)
    time.sleep(3)
    m = Maschine(os.path.join(D, "mon.sock"), BREITE, HOEHE)

    # MENUE AUF -- UND WARTEN, BIS DER SERVER ES GEMELDET HAT.
    #
    # Der erste Versuch nahm die Lage 2,5 s nach dem Klick. Die Leiste
    # sagte da schon `startmenue auf`, das FENSTER stand aber noch nicht
    # in der Fensterliste: die Liste schreibt der Server nur, wenn er
    # ohnehin malt, und zwischen Klick und naechstem Anstrich liegt
    # mehr als eine Sekunde. Gemessen: `taskbar: click x=18 y=20
    # hits=start` und `taskbar: startmenue auf` waren da, `wm: fen ...
    # w=440 h=300` nicht -- und das Skript brach ab, obwohl das Menue
    # offen war. Also wird auf die MELDUNG gewartet und nicht auf eine
    # Frist.
    lage = None
    for versuch in range(4):
        m.klick_auf(18, HOEHE - 20)
        bis = time.time() + 12
        while time.time() < bis:
            lage = menue_lage(s())
            if lage:
                break
            time.sleep(0.5)
        if lage:
            break
        # Nicht aufgegangen: einmal zu, dann wieder auf.
        m.klick_auf(18, HOEHE - 20)
        time.sleep(1.5)
    print("Menuelage: %s" % (lage,), flush=True)
    if not lage:
        print("kein Menue -- Abbruch")
        return 1
    mx, my, lx, ly, zh = lage

    # Jeden Eintrag anklicken. Sechs sind es (launcher: apps=6).
    for i in range(6):
        vor = s()
        zx, zy = mx + lx + 60, my + ly + zh // 2 + i * zh
        m.klick_auf(zx, zy)
        time.sleep(5.0)
        t = s()
        neu = t[len(vor):]
        st = re.findall(r"launcher: start ([^\s]+) pid=(-?\d+)", neu)
        rd = re.findall(r"(\w+): ready", neu)
        print("  Eintrag %d @(%d,%d): start=%s ready=%s"
              % (i, zx, zy, st, rd), flush=True)
        m.foto(os.path.join(SHOTS, "app-%d.png" % i))
        # Menue wieder auf fuer den naechsten
        m.klick_auf(18, HOEHE - 20)
        time.sleep(1.2)
        m.klick_auf(18, HOEHE - 20)
        time.sleep(2.0)

    t = s()
    print("\nalle 'launcher: start': %s"
          % re.findall(r"launcher: start ([^\s]+) pid=(-?\d+)", t), flush=True)
    print("umschaltbare Fenster: %s" % offen(t), flush=True)

    # Und jetzt Alt+Tab, mit mehr als einem Fenster.
    vor_f = len(re.findall(r"wm: fokus", t))
    b1 = os.path.join(SHOTS, "vor-alttab.png")
    m.foto(b1)
    m.sag("sendkey alt-tab", 0.25)
    time.sleep(2.0)
    b2 = os.path.join(SHOTS, "nach-alttab.png")
    m.foto(b2)
    t = s()
    print("wm: hot   : %s"
          % re.findall(r"wm: hot c=\d+ mod=\d+ act=\d+ getan=\d+", t)[-3:],
          flush=True)
    print("wm: fokus : %d -> %d, zuletzt %s"
          % (vor_f, len(re.findall(r"wm: fokus", t)),
             re.findall(r"wm: fokus id=\d+ vor=\d+", t)[-3:]), flush=True)
    m.sag("quit", 0.2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
