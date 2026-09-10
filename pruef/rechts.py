#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""rechts.py -- RECHTSKLICK AUF EINEN FENSTERKNOPF.

    python3 rechts.py <name> <breite> <hoehe> <uiscale>

Justins Vorgabe E, zweiter Teil: Rechtsklick auf ein Taskleisten-Symbol
-> Kontextmenue. Gemessen wird, dass

  1. das Menue AUFGEHT     (`taskbar: kontext btn=`)
  2. ein Punkt WIRKT       (`taskbar: kontext w=`)
  3. nichts dabei stirbt   (keine panic-Zeile)

Die rechte Taste ist im QEMU-Monitor `mouse_button 2` -- dieselbe
Zaehlung wie im PS/2-Baustein (links 1, rechts 2, Mitte 4).
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

NAME = sys.argv[1] if len(sys.argv) > 1 else "rechts"
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
    print("%-7s %-42s %-11s %s" % (nr, was[:42], erg, str(beleg)[:60]),
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

    # Ein Fenster her, damit es einen Fensterknopf gibt
    m.taste("meta_l")
    time.sleep(2)
    m.tippe("term")
    time.sleep(2)
    m.taste("ret")
    time.sleep(6)

    # DAS STARTMENUE WIEDER ZUMACHEN. Es liegt auf Ebene 2 (L_TOP) und
    # ist 880x600 gross -- es deckt die Stelle ab, an der gleich das
    # Kontextmenue aufklappt, und schluckt den Klick darauf. Gemessen:
    # `wm: fen i=4 id=11 x=8 y=792 w=880 h=600 lay=2`, und im Menue kam
    # nie eine `wlib: mnklick`-Zeile an.
    m.taste("esc")
    time.sleep(1.5)
    s = serial()
    bar_top = HOEHE - 80 if SCALE == 2 else HOEHE - 40
    b = re.findall(r"taskbar: btn i=(\d+) id=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", s)
    if not b:
        merke("1.1", "Fensterknopf da", "NEIN")
        return
    i, x, y, w, h = (int(v) for v in b[-1])
    zx, zy = x + w // 2, bar_top + y + h // 2
    merke("1.1", "Fensterknopf da", "ja", "x=%d y=%d" % (zx, zy))

    vor = len(serial())
    m.gehe(zx, zy)
    time.sleep(0.6)
    m.klick(2)               # rechte Taste
    time.sleep(2.5)
    neu = serial()[vor:]
    merke("2.1", "Kontextmenue geht auf",
          "ja" if "kontext btn=" in neu else "NEIN",
          [z for z in neu.splitlines() if "kontext" in z][:2])
    m.foto(os.path.join(SHOTS, "01-kontext.png"))

    # NICHT RATEN, WO DER PUNKT LIEGT: das Menuefenster meldet seine
    # Lage selbst (`wm: fen ... tp=30` = dreissig Punkte Titelleiste).
    # Der erste Eintrag beginnt unter dem Titel; ein Klick auf gut
    # Glueck landete im ersten Anlauf UNTER dem Menue.
    s2 = serial()
    mf = re.findall(r"wm: fen i=\d+ id=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+) "
                    r"lay=1 fl=0 z=\d+ malen=\d+ px=\d+ tx=\d+ tb=\d+ tp=(\d+)", s2)
    ziel = None
    for mx, my, mw, mh, tp in mf:
        mx, my, mw, mh, tp = (int(v) for v in (mx, my, mw, mh, tp))
        # das Menue ist schmal und steht ueber der Leiste
        if mw < 400 and my > HOEHE // 2:
            ziel = (mx + mw // 2, my + tp + 16)
    if ziel is None:
        ziel = (zx + 20, zy - 60)
    merke("2.15", "erster Menuepunkt bei", "%d,%d" % ziel)
    vor = len(serial())
    m.klick_auf(ziel[0], ziel[1])
    time.sleep(2.5)
    neu = serial()[vor:]
    merke("2.2", "Punkt gewaehlt und ausgefuehrt",
          "ja" if "kontext w=" in neu else "NEIN",
          [z for z in neu.splitlines() if "kontext" in z][:2])
    m.foto(os.path.join(SHOTS, "02-danach.png"))

    s = serial()
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
