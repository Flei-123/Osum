#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""probe1.py -- die zwei Sperrfehler nachmessen (Runde TUERSCHLOSS).

Fehler 1: kein Programm startet (pid=-22).
Fehler 2: die Shell stirbt endlos (`sh: ready, osum` / `sh: bye`).

Gemessen wird am SERIELLEN MITSCHNITT und am BILD -- nicht behauptet.
"""
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from klick import Maschine

HIER = os.path.dirname(os.path.abspath(__file__))
NAME = sys.argv[1] if len(sys.argv) > 1 else "p1"
BREITE = int(sys.argv[2]) if len(sys.argv) > 2 else 1280
HOEHE = int(sys.argv[3]) if len(sys.argv) > 3 else 800
D = os.path.join(HIER, "laeufe", NAME)
SHOTS = os.path.join(HIER, "shots")
os.makedirs(SHOTS, exist_ok=True)


def serial():
    p = os.path.join(D, "serial.txt")
    if not os.path.exists(p):
        return ""
    return open(p, encoding="utf-8", errors="replace").read()


def start():
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(BREITE), str(HOEHE)], check=True,
                   capture_output=True, text=True, timeout=60)


def warte_auf_schreibtisch(frist=90):
    bis = time.time() + frist
    while time.time() < bis:
        s = serial()
        if "desktop: ready" in s or "taskbar: STEHT" in s:
            return time.time()
        time.sleep(0.5)
    return None


def main():
    ergebnis = {}
    start()
    t0 = time.time()
    fertig = warte_auf_schreibtisch()
    ergebnis["boot_s"] = round(fertig - t0, 1) if fertig else None
    print("BOOT: %s s" % ergebnis["boot_s"])

    m = Maschine(os.path.join(D, "mon.sock"), BREITE, HOEHE)
    m.foto(os.path.join(SHOTS, "%s-01-schreibtisch.png" % NAME))

    # --- Startmenue per Maus aufmachen (der Weg, der in DURCHKLICK ging)
    m.klick_auf(18, HOEHE - 20)
    time.sleep(2.0)
    m.foto(os.path.join(SHOTS, "%s-02-startmenue.png" % NAME))

    s = serial()
    # Was steht im Starter?
    treffer = re.findall(r"launcher: treffer i=(\d+) name=\[([^\]]*)\]", s)
    ergebnis["apps_im_menue"] = [t[1] for t in treffer]
    print("APPS IM MENUE:", ergebnis["apps_im_menue"])

    # --- den ersten Eintrag anklicken (Datei-Explorer)
    # Der Starter steht ueber dem Startknopf; die Eintraege liegen
    # untereinander. Ort aus der seriellen Meldung, wenn sie da ist.
    mm = re.search(r"launcher: fenster x=(\d+) y=(\d+) w=(\d+) h=(\d+)", s)
    print("launcher-fenster:", mm.group(0) if mm else "keine Meldung")

    vor = len(re.findall(r"launcher: start", s))
    # Eintraege des Starters: erste Zeile der Liste. Wir klicken in die
    # obere Haelfte des Starterfensters, wo die Treffer stehen.
    if mm:
        fx, fy, fw, fh = (int(g) for g in mm.groups())
        m.klick_auf(fx + fw // 2, fy + 70)
    else:
        m.klick_auf(120, HOEHE - 120)
    time.sleep(3.0)
    m.foto(os.path.join(SHOTS, "%s-03-nach-klick.png" % NAME))

    s = serial()
    starts = re.findall(r"launcher: start (\S+) pid=(-?\d+)", s)
    ergebnis["starts"] = starts
    print("LAUNCHER-STARTS:", starts)
    gute = [x for x in starts if not x[1].startswith("-") and x[1] != "0"]
    ergebnis["starts_ok"] = len(gute)
    ergebnis["starts_fehler"] = len([x for x in starts if x[1].startswith("-")])
    print("  davon pid>0: %d, davon negativ: %d"
          % (ergebnis["starts_ok"], ergebnis["starts_fehler"]))

    # --- Fehler 2: stirbt die Shell?
    ergebnis["sh_ready"] = len(re.findall(r"sh: ready, osum", s))
    ergebnis["sh_bye"] = len(re.findall(r"sh: bye", s))
    print("SHELL: ready=%d bye=%d" % (ergebnis["sh_ready"], ergebnis["sh_bye"]))

    # --- 30 s laufen lassen und noch einmal zaehlen: waechst es?
    time.sleep(30)
    s = serial()
    r2 = len(re.findall(r"sh: ready, osum", s))
    b2 = len(re.findall(r"sh: bye", s))
    ergebnis["sh_ready_nach30"] = r2
    ergebnis["sh_bye_nach30"] = b2
    print("SHELL nach 30 s: ready=%d bye=%d  (Zuwachs %d/%d)"
          % (r2, b2, r2 - ergebnis["sh_ready"], b2 - ergebnis["sh_bye"]))

    # --- Fenster: wie viele stehen?
    fenster = re.findall(r"wm: fenster n=(\d+)", s)
    ergebnis["fenster"] = fenster[-5:] if fenster else []
    ergebnis["panik"] = len(re.findall(r"PANIK|#PF|#UD|panic", s))
    print("PANIK/Ausnahmen:", ergebnis["panik"])

    m.foto(os.path.join(SHOTS, "%s-04-nach-30s.png" % NAME))

    with open(os.path.join(D, "ergebnis.txt"), "w") as f:
        for k, v in ergebnis.items():
            f.write("%s = %r\n" % (k, v))
    print("\n-> %s/ergebnis.txt" % D)


if __name__ == "__main__":
    main()
