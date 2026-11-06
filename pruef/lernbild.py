#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    lernbild.py -- ein photo mit BEKANNTEM Text erzeugen, um die
    python3 lernbild.py <name>
"""
import os
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
from click_driver import Maschine
import read_all

NAME = sys.argv[1] if len(sys.argv) > 1 else "lern"
WIDTH, HEIGHT = 1280, 800
D = os.path.join(HIER, "laeufe", NAME)
SHOTS = os.path.join(HIER, "shots", NAME)
os.makedirs(SHOTS, exist_ok=True)
SER = os.path.join(D, "serial.txt")
RAND, TITLE = 2, 22

# Was getippt wird. Kleinbuchstaben zuerst, weil sie im Ergebnis am
# haeufigsten vorkommen; die Zeilen bleiben kurz genug fuer 56 Spalten.
ROWS = [
    "abcdefghijklmnopqrstuvwxyz",
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    "0123456789 .,:;-_/()[]=+*",
]


def s():
    return read_all.text(SER)


def main():
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(WIDTH), str(HEIGHT)], check=True,
                   capture_output=True, text=True, timeout=60)
    t0 = time.time()
    while time.time() - t0 < 120 and "taskbar: start x=" not in s():
        time.sleep(0.3)
    print("BOOT: %.1f s" % (time.time() - t0))
    time.sleep(2.5)
    m = Maschine(os.path.join(D, "mon.sock"), WIDTH, HEIGHT)

    term = None
    bis = time.time() + 60
    while time.time() < bis and term is None:
        for i, lagen in read_all.window(s()).items():
            for x, y, w, h in lagen:
                if w == 560 and h == 380:
                    term = (i, x, y, w, h)
        if term is None:
            time.sleep(1.0)
    _i, tx, ty, tw, th = term
    m.klick_auf(tx + RAND + tw // 2, ty + TITLE + th // 2)
    time.sleep(1.5)

    # `clear` gibt es vielleicht nicht -- also einfach genug Leerzeilen,
    # damit oben nichts Altes mehr steht.
    for _ in range(3):
        m.key_press("ret")
        time.sleep(0.3)

    erwartet = []
    for z in ROWS:
        m.tippe("echo " + z)
        m.key_press("ret")
        time.sleep(2.2)
        # Die Shell zeigt die getippte Zeile UND ihre Ausgabe.
        erwartet.append("osum$ echo " + z)
        erwartet.append(z)
    p = os.path.join(SHOTS, "lernbild.ppm")
    m.photo(p)
    with open(os.path.join(SHOTS, "erwartet.txt"), "w") as f:
        f.write("\n".join(erwartet))
    print("Foto: %s" % p)
    print("erwartet:\n%s" % "\n".join(erwartet))
    return 0


if __name__ == "__main__":
    sys.exit(main())
