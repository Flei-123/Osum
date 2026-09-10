#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""zeigerprobe.py -- KOMMT DER ZEIGER DA AN, WO ER HIN SOLL?

    python3 zeigerprobe.py [name] [breite] [hoehe]

WARUM DIESE MESSUNG. 4.1 (Fenster verschieben) und 4.2 (Groesse) sagen
beide "GEHT NICHT" -- und zwar auf dem ALTEN Abbild (merge8) genauso wie
auf dem neuen. Eine Regression dieser Runde ist es damit schon einmal
nicht. Bleibt die Frage, ob der Fensterserver den Griff verfehlt oder ob
der ZEIGER gar nicht dort ist, wo das Skript ihn glaubt.

Der Verdacht kommt aus zwei Zahlen auf der Leitung:

    ps2m.adopt:  S_X = w/2, S_Y = h/2      -> 640,400 bei 1280x800
    gemessen:    xy=639,399

Der Zeiger startet also in der Mitte, und `klick.py` faehrt ihn mit
RELATIVEN `mouse_move`-Schritten. Dessen `ecke()` schickt zwoelfmal
(-200,-200) und nimmt danach an, der Zeiger stehe auf (0,0) -- was nur
stimmt, wenn der Anschlag wirklich haelt.

Diese Probe faehrt eine Handvoll bekannter Orte an und liest JEDES MAL
nach, wo der Kern den Zeiger sieht. Die Abweichung ist die Antwort.

WIE DER ORT AUSGELESEN WIRD. Der Puls schreibt `xy=<x>,<y>` -- aber
selten. Also wird nicht darauf gewartet, sondern der Zeiger bewegt und
danach so lange gelesen, bis eine NEUE xy-Zeile kommt.
"""
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
from klick import Maschine

NAME = sys.argv[1] if len(sys.argv) > 1 else "zp"
BREITE = int(sys.argv[2]) if len(sys.argv) > 2 else 1280
HOEHE = int(sys.argv[3]) if len(sys.argv) > 3 else 800
D = os.path.join(HIER, "laeufe", NAME)
SER = os.path.join(D, "serial.txt")


def s():
    try:
        return open(SER, "rb").read().replace(b"\x00", b"").decode(
            "utf-8", "replace")
    except OSError:
        return ""


def xy_zahl():
    v = re.findall(r"xy=(\d+),(\d+)", s())
    return (int(v[-1][0]), int(v[-1][1])) if v else None


def warte_neues_xy(alt, frist=40):
    bis = time.time() + frist
    while time.time() < bis:
        v = re.findall(r"xy=(\d+),(\d+)", s())
        if v and len(v) > alt:
            return (int(v[-1][0]), int(v[-1][1])), len(v)
        time.sleep(0.4)
    v = re.findall(r"xy=(\d+),(\d+)", s())
    return ((int(v[-1][0]), int(v[-1][1])) if v else None), len(v)


def main():
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(BREITE), str(HOEHE)], check=True,
                   capture_output=True, text=True, timeout=60)
    t0 = time.time()
    while time.time() - t0 < 180:
        if "taskbar: start x=" in s():
            break
        time.sleep(0.3)
    print("hochgefahren nach %.1f s" % (time.time() - t0), flush=True)
    time.sleep(4)
    m = Maschine(os.path.join(D, "mon.sock"), BREITE, HOEHE)

    n = len(re.findall(r"xy=(\d+),(\d+)", s()))
    print("Zeigerlage beim Start: %s" % (xy_zahl(),), flush=True)

    ziele = [(66, 51), (580, 436), (18, HOEHE - 20), (300, 200), (640, 400)]
    print("\n%-14s %-14s %s" % ("gewollt", "gemessen", "Abweichung"))
    for (zx, zy) in ziele:
        m.gehe(zx, zy)
        time.sleep(1.0)
        ist, n = warte_neues_xy(n, 40)
        if ist:
            print("%-14s %-14s dx=%+d dy=%+d"
                  % ("(%d,%d)" % (zx, zy), "(%d,%d)" % ist,
                     ist[0] - zx, ist[1] - zy), flush=True)
        else:
            print("%-14s %-14s -" % ("(%d,%d)" % (zx, zy), "keine Meldung"),
                  flush=True)

    m.sag("quit", 0.2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
