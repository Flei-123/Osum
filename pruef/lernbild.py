#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""lernbild.py -- ein Foto mit BEKANNTEM Text erzeugen, um die
Terminalschrift einzulesen.

    python3 lernbild.py <name>

Es wird `echo <alphabet>` getippt, fotografiert, und der getippte Text
danebengelegt. `lies3.py --lerne` zieht daraus die Muster.

WARUM NICHT DIE TABELLE AUS kernel/gfx/font.fi NACHBAUEN: sie liegt dort
als zehn Zeichenkettenstuecke im Datenbereich, und ein Nachbau waere
eine zweite Quelle fuer dieselbe Wahrheit -- genau das, was dieses
Projekt sonst ueberall vermeidet. Eingelesen ist sie richtig oder
falsch, und ob sie richtig ist, sagt der naechste Lauf.
"""
import os
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
from klick import Maschine
import lesen

NAME = sys.argv[1] if len(sys.argv) > 1 else "lern"
BREITE, HOEHE = 1280, 800
D = os.path.join(HIER, "laeufe", NAME)
SHOTS = os.path.join(HIER, "shots", NAME)
os.makedirs(SHOTS, exist_ok=True)
SER = os.path.join(D, "serial.txt")
RAND, TITEL = 2, 22

# Was getippt wird. Kleinbuchstaben zuerst, weil sie im Ergebnis am
# haeufigsten vorkommen; die Zeilen bleiben kurz genug fuer 56 Spalten.
ZEILEN = [
    "abcdefghijklmnopqrstuvwxyz",
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    "0123456789 .,:;-_/()[]=+*",
]


def s():
    return lesen.text(SER)


def main():
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(BREITE), str(HOEHE)], check=True,
                   capture_output=True, text=True, timeout=60)
    t0 = time.time()
    while time.time() - t0 < 120 and "taskbar: start x=" not in s():
        time.sleep(0.3)
    print("BOOT: %.1f s" % (time.time() - t0))
    time.sleep(2.5)
    m = Maschine(os.path.join(D, "mon.sock"), BREITE, HOEHE)

    term = None
    bis = time.time() + 60
    while time.time() < bis and term is None:
        for i, lagen in lesen.fenster(s()).items():
            for x, y, w, h in lagen:
                if w == 560 and h == 380:
                    term = (i, x, y, w, h)
        if term is None:
            time.sleep(1.0)
    _i, tx, ty, tw, th = term
    m.klick_auf(tx + RAND + tw // 2, ty + TITEL + th // 2)
    time.sleep(1.5)

    # `clear` gibt es vielleicht nicht -- also einfach genug Leerzeilen,
    # damit oben nichts Altes mehr steht.
    for _ in range(3):
        m.taste("ret")
        time.sleep(0.3)

    erwartet = []
    for z in ZEILEN:
        m.tippe("echo " + z)
        m.taste("ret")
        time.sleep(2.2)
        # Die Shell zeigt die getippte Zeile UND ihre Ausgabe.
        erwartet.append("osum$ echo " + z)
        erwartet.append(z)
    p = os.path.join(SHOTS, "lernbild.ppm")
    m.foto(p)
    with open(os.path.join(SHOTS, "erwartet.txt"), "w") as f:
        f.write("\n".join(erwartet))
    print("Foto: %s" % p)
    print("erwartet:\n%s" % "\n".join(erwartet))
    return 0


if __name__ == "__main__":
    sys.exit(main())
