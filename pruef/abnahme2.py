#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    acceptance2.py -- DIE ACCEPTANCE DER RUNDE ECHTHARDWARE-2.
    python3 acceptance2.py <name> <width> <height> <uiscale>
"""
import json
import os
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
from click_driver import Maschine

NAME = sys.argv[1] if len(sys.argv) > 1 else "ab2"
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
    print("%-7s %-44s %-11s %s" % (nr, was[:44], erg, str(beleg)[:66]),
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
    extra = "uiscale=%d shape=osum" % SCALE if SCALE != 1 else "shape=osum"
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(WIDTH), str(HEIGHT), extra],
                   check=True, cwd=HIER,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    m = Maschine(os.path.join(D, "mon.sock"), WIDTH, HEIGHT)
    m.verbinde()
    merke("0.1", "Leiste steht", "ja" if wait_for("taskbar: state") else "NEIN")
    time.sleep(4)
    s = serial()
    lang = [z for z in s.splitlines() if "lang=" in z]
    merke("0.2", "Sprache der Oberflaeche", "gemessen", lang[:2])

    # ---------------------------------------------------- 01 STARTMENUE
    m.key_press("meta_l")
    time.sleep(2.5)
    m.tippe("ter")
    time.sleep(2.5)
    m.photo(os.path.join(SHOTS, "01-startmenue.png"))
    s = serial()
    su = [z for z in s.splitlines() if "launcher: suche" in z]
    merke("1.1", "Startmenue offen + 'ter' gefiltert",
          "ja" if su else "NEIN", su[-2:])

    # Enter startet den ersten Treffer
    m.key_press("ret")
    time.sleep(4)
    merke("1.2", "Enter startet", "ja" if "elf: start" in serial() else "NEIN",
          [z for z in serial().splitlines() if "elf: start" in z][-1:])
    m.photo(os.path.join(SHOTS, "05-terminal.png"))

    # ------------------------------------------------------ 02 EXPLORER
    vor = len(serial())
    m.key_press("meta_l")
    time.sleep(2)
    for _ in range(24):
        m.key_press("backspace")
    time.sleep(1)
    m.tippe("expl")
    time.sleep(2)
    m.key_press("ret")
    time.sleep(5)
    m.photo(os.path.join(SHOTS, "02-explorer.png"))
    renewed = serial()[vor:]
    sp = [z for z in renewed.splitlines() if "explorer: spalten" in z]
    merke("2.1", "Explorer offen, Spalten", "ja" if sp else "?", sp[-1:])

    # -------------------------------------------------- 03 EINSTELLUNGEN
    vor = len(serial())
    m.key_press("meta_l")
    time.sleep(2)
    # DAS FELD LEEREN. Es traegt noch "explorer" aus dem Schritt davor;
    # "settings" haenge sich daran, der Starter fand folgerichtig nichts,
    # und das sah aus wie "Einstellungen startet nicht".
    for _ in range(24):
        m.key_press("backspace")
    time.sleep(1)
    m.tippe("sett")
    time.sleep(2)
    m.key_press("ret")
    time.sleep(6)
    m.photo(os.path.join(SHOTS, "03-einstellungen.png"))
    renewed = serial()[vor:]
    merke("3.1", "Einstellungen gestartet",
          "ja" if "elf: start" in renewed else "NEIN",
          [z for z in renewed.splitlines() if "elf: start" in z][-1:])
    merke("3.2", "appdir INFO-Fehler",
          "JA (Fehler)" if "laenger als" in serial() else "nein")

    # ------------------------------------------------ 04 KONTROLLZENTRUM
    vor = len(serial())
    m.klick_auf(WIDTH - 60, HEIGHT - 40)
    time.sleep(3)
    m.photo(os.path.join(SHOTS, "04-kontrollzentrum.png"))
    renewed = serial()[vor:]
    merke("4.1", "Kontrollzentrum reagiert", "gemessen",
          [z for z in renewed.splitlines() if "qs" in z or "kachel" in z][:3])

    # jede Kachel anklicken -- Justins "danach geht gar nichts mehr"
    kachel_panics = []
    for k in range(6):
        vor = len(serial())
        m.klick_auf(WIDTH - 300 + (k % 3) * 90, HEIGHT - 320 + (k // 3) * 90)
        time.sleep(1.5)
        renewed = serial()[vor:]
        if "panic" in renewed:
            kachel_panics.append("Kachel %d: %s" % (k, renewed[:120]))
    merke("4.2", "jede Kachel geklickt, panics",
          "KEINE" if not kachel_panics else "JA", kachel_panics[:3])
    m.photo(os.path.join(SHOTS, "04b-kacheln.png"))

    # ------------------------------------------------------ NAHAUFNAHMEN
    voll = os.path.join(SHOTS, "voll.png")
    m.photo(voll)
    try:
        from PIL import Image
        im = Image.open(voll)
        im.crop((0, HEIGHT - 120, 600, HEIGHT)).save(
            os.path.join(SHOTS, "06-leiste.png"))
        im.crop((WIDTH - 600, HEIGHT - 120, WIDTH, HEIGHT)).save(
            os.path.join(SHOTS, "07-tray.png"))
        merke("6.1", "Nahaufnahmen geschnitten", "ja")
    except Exception as e:
        merke("6.1", "Nahaufnahmen geschnitten", "NEIN", e)

    # ---------------------------------------------------------- PANICS
    s = serial()
    p = [z.strip() for z in s.splitlines() if "panic:" in z]
    merke("9.1", "panics im GANZEN Durchklick",
          "KEINE" if not p else "JA (%d)" % len(p), p[:5])
    merke("9.2", "Symbolbreiten (Bitmap)", "gemessen",
          [z for z in s.splitlines() if "taskbar: sym" in z][-2:])

    with open(os.path.join(D, "befund.json"), "w") as f:
        json.dump(BEFUND, f, indent=1, ensure_ascii=False)
    try:
        m.say("quit")
    except Exception:
        pass
    print("\nBilder: %s" % SHOTS)


if __name__ == "__main__":
    main()
