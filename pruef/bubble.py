#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    bubble.py -- DIE INFOBLASE, GEMESSEN.
    python3 bubble.py <name> <width> <height> <uiscale>
"""
import json
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
from click_driver import Maschine

NAME = sys.argv[1] if len(sys.argv) > 1 else "blase"
WIDTH = int(sys.argv[2]) if len(sys.argv) > 2 else 2560
HEIGHT = int(sys.argv[3]) if len(sys.argv) > 3 else 1440
SCALE = int(sys.argv[4]) if len(sys.argv) > 4 else 2

D = os.path.join(HIER, "runs", NAME)
SHOTS = os.path.join(HIER, "shots", NAME)
os.makedirs(SHOTS, exist_ok=True)
SER = os.path.join(D, "serial.txt")
BEFUND = []


def merke(nr, was, erg, beleg=""):
    BEFUND.append({"nr": nr, "was": was, "ergebnis": erg,
                   "beleg": str(beleg)[:400]})
    print("%-7s %-42s %-11s %s" % (nr, was[:42], erg, str(beleg)[:62]),
          flush=True)


def serial():
    try:
        with open(SER, "rb") as f:
            return f.read().decode("utf-8", "replace")
    except OSError:
        return ""


def wait_for(mark, deadline=90):
    t0 = time.time()
    while time.time() - t0 < deadline:
        if mark in serial():
            return True
        time.sleep(2)
    return False


def main():
    extra = ("uiscale=%d " % SCALE if SCALE != 1 else "") + "shape=osum"
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(WIDTH), str(HEIGHT), extra],
                   check=True, cwd=HIER,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    m = Maschine(os.path.join(D, "mon.sock"), WIDTH, HEIGHT)
    m.verbinde()
    merke("0.1", "Leiste steht", "ja" if wait_for("taskbar: state") else "NEIN")
    time.sleep(4)

    # Ein Fenster oeffnen, damit es einen Fensterknopf mit Titel gibt.
    m.key_press("meta_l")
    time.sleep(2)
    m.tippe("term")
    time.sleep(2)
    m.key_press("ret")
    time.sleep(5)

    s = serial()
    bar_top = HEIGHT - 80 if SCALE == 2 else HEIGHT - 40
    ziele = []
    b = re.findall(r"taskbar: btn i=(\d+) id=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", s)
    if b:
        i, x, y, w, h = (int(v) for v in b[-1])
        ziele.append(("Fensterknopf", x + w // 2, bar_top + y + h // 2))
    f = re.findall(r"taskbar: field net x=(\d+) y=(\d+) w=(\d+) h=(\d+)", s)
    if f:
        x, y, w, h = (int(v) for v in f[-1])
        ziele.append(("Netzfeld", x + w // 2, bar_top + y + h // 2))
    st = re.findall(r"taskbar: start x=(\d+) y=(\d+) w=(\d+) h=(\d+)", s)
    if st:
        x, y, w, h = (int(v) for v in st[-1])
        ziele.append(("Startknopf", x + w // 2, bar_top + y + h // 2))

    for name, zx, zy in ziele:
        # erst weit weg, damit die Marke wirklich wechselt
        m.go_to(WIDTH // 2, HEIGHT // 2)
        time.sleep(1.0)
        vor = len(serial())
        m.go_to(zx, zy)
        time.sleep(2.5)          # deutlich mehr als die halbe Sekunde
        renewed = serial()[vor:]
        tips = [z for z in renewed.splitlines() if "wlib: tip [" in z]
        # ERST nachsehen, DANN fotografieren: die Blase entsteht im
        # naechsten Umlauf der Leiste, und ein Foto unmittelbar nach
        # der Meldung zeigt sie noch nicht. Im ersten Lauf dieser
        # Runde sah das aus wie "gemeldet, aber unsichtbar".
        time.sleep(1.5)
        m.photo(os.path.join(SHOTS, "tip-%s.png" % name))
        merke("T-%s" % name, "Blase ueber %s" % name,
              "ja" if tips else "NEIN", tips[:1])

    # Verlassen schliesst sie wieder
    vor = len(serial())
    m.go_to(WIDTH // 2, HEIGHT // 3)
    time.sleep(1.5)
    renewed = serial()[vor:]
    merke("T-zu", "Blase geht beim Verlassen zu",
          "ja" if "tip zu" in renewed else "NEIN",
          [z for z in renewed.splitlines() if "tip" in z][:2])

    s = serial()
    p = [z.strip() for z in s.splitlines() if "panic:" in z]
    merke("9.1", "panics", "KEINE" if not p else "JA", p[:3])
    with open(os.path.join(D, "befund.json"), "w") as f2:
        json.dump(BEFUND, f2, indent=1, ensure_ascii=False)
    try:
        m.say("quit")
    except Exception:
        pass


if __name__ == "__main__":
    main()
