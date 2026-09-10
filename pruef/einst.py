#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""einst.py -- DIE EINSTELLUNGEN, GEOEFFNET UND ANGESEHEN.

    python3 einst.py <name> <breite> <hoehe> <uiscale>

Justins Befund A2: "Einstellungen-Fenster leer/weiss". Ursache war der
1023-Oktett-Puffer in appdir.fi (settings.osp/INFO ist 2101 lang). Der
Fix ist drin -- dieser Lauf beweist, dass jetzt WIRKLICH etwas im
Fenster steht, und zwar aus dem Bild und nicht aus der Leitung.

Das Suchfeld wird vorher GELEERT. In der Abnahme davor stand noch
"explorer" darin, "settings" wurde angehaengt, und der Starter fand
folgerichtig nichts -- das sah aus wie "Einstellungen startet nicht"
und war ein voller Puffer im Suchfeld.
"""
import json
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
from klick import Maschine

NAME = sys.argv[1] if len(sys.argv) > 1 else "einst"
BREITE = int(sys.argv[2]) if len(sys.argv) > 2 else 2560
HOEHE = int(sys.argv[3]) if len(sys.argv) > 3 else 1440
SCALE = int(sys.argv[4]) if len(sys.argv) > 4 else 2

D = os.path.join(HIER, "laeufe", NAME)
SHOTS = os.path.join(HIER, "shots", NAME)
os.makedirs(SHOTS, exist_ok=True)
SER = os.path.join(D, "serial.txt")
BEFUND = []


def merke(nr, was, erg, beleg=""):
    BEFUND.append({"nr": nr, "was": was, "ergebnis": erg,
                   "beleg": str(beleg)[:400]})
    print("%-7s %-44s %-11s %s" % (nr, was[:44], erg, str(beleg)[:60]),
          flush=True)


def serial():
    try:
        with open(SER, "rb") as f:
            return f.read().decode("utf-8", "replace")
    except OSError:
        return ""


def warte_auf(marke, frist=90):
    t0 = time.time()
    while time.time() - t0 < frist:
        if marke in serial():
            return True
        time.sleep(2)
    return False


def main():
    extra = ("uiscale=%d " % SCALE if SCALE != 1 else "") + "shape=osum"
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(BREITE), str(HOEHE), extra],
                   check=True, cwd=HIER,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    m = Maschine(os.path.join(D, "mon.sock"), BREITE, HOEHE)
    m.verbinde()
    merke("0.1", "Leiste steht", "ja" if warte_auf("taskbar: state") else "NEIN")
    time.sleep(4)

    # Startmenue auf, Feld leeren, tippen
    m.taste("meta_l")
    time.sleep(2.5)
    for _ in range(24):
        m.taste("backspace")
    time.sleep(1)
    m.tippe("sett")
    time.sleep(2.5)
    s = serial()
    tr = [z for z in s.splitlines() if "launcher: treffer" in z]
    merke("1.1", "Starter findet die Einstellungen",
          "ja" if any("Settings" in z for z in tr) else "NEIN", tr[-2:])
    m.foto(os.path.join(SHOTS, "01-suche.png"))

    vor = len(serial())
    m.taste("ret")
    time.sleep(8)
    neu = serial()[vor:]
    merke("1.2", "gestartet", "ja" if "elf: start" in neu else "NEIN",
          [z for z in neu.splitlines() if "elf: start" in z][-1:])
    m.foto(os.path.join(SHOTS, "02-einstellungen.png"))

    # Wo steht das Fenster?
    s = serial()
    fen = re.findall(r"wm: fen i=\d+ id=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", s)
    merke("2.1", "Fenster auf dem Schirm", "gemessen", fen[-6:])
    merke("2.2", "appdir INFO-Fehler",
          "JA" if "laenger als" in s else "nein")
    p = [z.strip() for z in s.splitlines() if "panic:" in z]
    merke("9.1", "panics", "KEINE" if not p else "JA", p[:3])

    with open(os.path.join(D, "befund.json"), "w") as f:
        json.dump(BEFUND, f, indent=1, ensure_ascii=False)
    try:
        m.sag("quit")
    except Exception:
        pass


if __name__ == "__main__":
    main()
