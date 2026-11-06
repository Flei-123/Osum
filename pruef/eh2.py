#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    eh2.py -- RUNDE ECHTHARDWARE-2: Justins Durchklick, nachgestellt.
    python3 eh2.py <name> <width> <height> [uiscale]
"""
import json
import os
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HIER, ".."))
sys.path.insert(0, HIER)
from click_driver import Maschine

NAME = sys.argv[1] if len(sys.argv) > 1 else "eh2"
WIDTH = int(sys.argv[2]) if len(sys.argv) > 2 else 2560
HEIGHT = int(sys.argv[3]) if len(sys.argv) > 3 else 1440
SCALE = int(sys.argv[4]) if len(sys.argv) > 4 else 2

D = os.path.join(HIER, "laeufe", NAME)
SHOTS = os.path.join(HIER, "shots", NAME)
os.makedirs(SHOTS, exist_ok=True)
SER = os.path.join(D, "serial.txt")

BEFUND = []


def merke(nr, was, erg, beleg=""):
    BEFUND.append({"nr": nr, "was": was, "ergebnis": erg,
                   "beleg": str(beleg)[:400]})
    print("%-7s %-46s %-10s %s" % (nr, was[:46], erg, str(beleg)[:70]),
          flush=True)


def serial():
    try:
        with open(SER, "rb") as f:
            return f.read().decode("utf-8", "replace")
    except OSError:
        return ""


def panics(s):
    out = []
    for z in s.splitlines():
        if "panic:" in z:
            out.append(z.strip())
    return out


def main():
    extra = "uiscale=%d shape=osum" % SCALE
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(WIDTH), str(HEIGHT), extra],
                   check=True, cwd=HIER,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    m = Maschine(os.path.join(D, "mon.sock"), WIDTH, HEIGHT)
    m.verbinde()
    # AKTIV WARTEN statt blind schlafen. Gemessen in dieser Runde: bei
    # 2560x1440 und uiscale=2 stand die Leiste nach 18 s noch nicht --
    # der Lauf mass dann die eigene Ungeduld und meldete "Super kommt
    # nicht an", obwohl auf der Leitung `driver=kbd` stand. Es wird
    # gewartet, bis die Leiste sich MELDET, hoechstens 90 s.
    t0 = time.time()
    while time.time() - t0 < 90:
        if "taskbar: state" in serial():
            break
        time.sleep(2)
    time.sleep(4)

    s = serial()
    merke("0.1", "gebootet, Leiste da", "ja" if "taskbar:" in s else "NEIN",
          [z for z in s.splitlines() if "osum " in z][-1:])
    merke("0.2", "uiscale wirklich %d" % SCALE,
          "ja" if ("scale=%d" % SCALE) in s or SCALE == 1 else "?",
          [z for z in s.splitlines() if "scale=" in z][:2])

    # ---------------------------------------------------- 1. SUPER-TASTE
    vor = len(serial())
    m.key_press("meta_l")
    time.sleep(2.5)
    s = serial()
    renewed = s[vor:]
    m.photo(os.path.join(SHOTS, "01-super.png"))
    merke("1.1", "Super: Klinke gemeldet",
          "ja" if "klinke" in renewed else "NEIN",
          [z for z in renewed.splitlines() if "klinke" in z][:2])
    merke("1.2", "Super: Startmenue offen",
          "ja" if "menue" in renewed or "launcher" in renewed else "NEIN",
          [z for z in renewed.splitlines() if "menue" in z or "launcher" in z][:3])

    # ------------------------------------------------ 2. TIPPEN + FILTER
    vor = len(serial())
    m.tippe("ter")
    time.sleep(2.5)
    renewed = serial()[vor:]
    m.photo(os.path.join(SHOTS, "02-tippen.png"))
    tr = [z for z in renewed.splitlines() if "suche" in z or "treffer" in z]
    merke("2.1", "Tippen 'ter' filtert", "ja" if tr else "NEIN", tr[:3])

    # ------------------------------------------------------- 3. ENTER
    vor = len(serial())
    m.key_press("ret")
    time.sleep(3.5)
    renewed = serial()[vor:]
    m.photo(os.path.join(SHOTS, "03-enter.png"))
    merke("3.1", "Enter startet ersten Treffer",
          "ja" if "start" in renewed else "NEIN",
          [z for z in renewed.splitlines() if "start" in z][:3])

    # --------------------------------------- 4. OS-SYMBOL LINKS UNTEN
    vor = len(serial())
    m.klick_auf(30, HEIGHT - 40)
    time.sleep(2.5)
    renewed = serial()[vor:]
    m.photo(os.path.join(SHOTS, "04-ossymbol.png"))
    merke("4.1", "Klick auf OS-Symbol oeffnet Menue",
          "ja" if ("menue" in renewed or "launcher" in renewed) else "NEIN",
          [z for z in renewed.splitlines()
           if "menue" in z or "launcher" in z or "klick" in z][:3])

    # ---------------------------------------------- 5. EINSTELLUNGEN
    vor = len(serial())
    m.say("sendkey ctrl-alt-f2")   # nur, damit die Leitung sich ruehrt
    time.sleep(0.5)
    s = serial()
    merke("5.1", "appdir INFO zu lang gemeldet",
          "JA (Fehler)" if "laenger als 1023" in s else "nein",
          [z for z in s.splitlines() if "laenger als 1023" in z][:3])

    # ----------------------------------------------------- 6. PANICS
    s = serial()
    p = panics(s)
    merke("6.1", "panics im ganzen Lauf", "KEINE" if not p else "JA", p[:5])

    # -------------------------------------------- 7. TASKLEISTE-MASSE
    sym = [z for z in s.splitlines() if "taskbar: sym" in z]
    merke("7.1", "Taskleisten-Symbolbreite", "gemessen", sym[-3:])
    spalt = [z for z in s.splitlines() if "explorer: spalten" in z]
    merke("7.2", "Explorer-Spalten", "gemessen", spalt[-2:])

    with open(os.path.join(D, "befund.json"), "w") as f:
        json.dump(BEFUND, f, indent=1, ensure_ascii=False)
    print("\n--- Bilder in %s" % SHOTS)
    try:
        m.say("quit")
    except Exception:
        pass


if __name__ == "__main__":
    main()
