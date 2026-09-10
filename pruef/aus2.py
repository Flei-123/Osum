#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""aus2.py -- warum `shutdown` nicht ausschaltet: NACHSEHEN, was die
Shell antwortet.

Der Vorlaeufer hat nur gemessen, dass der QEMU-Prozess weiterlaeuft.
Das ist richtig und sagt nicht, WARUM. Hier wird nach dem Befehl ein
Foto gemacht und darin nach den Fehlermeldungen gesucht, die
`kernel/user/shutdown.fi` selbst kennt:

    shutdown: /run/svc.cmd nicht schreibbar (root?)
    shutdown: init antwortet nicht -- selbst aus
    shutdown: der Kern hat nicht abgeschaltet

Dazu `shutdown -f` (ohne init) als Gegenprobe: geht das, liegt es an
init; geht es auch nicht, liegt es am Kern.
"""
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
from klick import Maschine
import lesen

NAME = sys.argv[1] if len(sys.argv) > 1 else "aus2"
BREITE, HOEHE = 1280, 800
D = os.path.join(HIER, "laeufe", NAME)
SHOTS = os.path.join(HIER, "shots", NAME)
os.makedirs(SHOTS, exist_ok=True)
SER = os.path.join(D, "serial.txt")
REPO = os.path.abspath(os.path.join(HIER, ".."))
MONO = os.path.join(REPO, "assets", "osum-mono.ttf")
SUCH = os.path.join(REPO, "tools", "usbimg", "suchtext.py")
RAND, TITEL = 2, 22


def s():
    return lesen.text(SER)


def suche(ppm, text):
    r = subprocess.run(["python3", SUCH, ppm, MONO, "16", text,
                        "--min", "50"], capture_output=True, text=True,
                       timeout=300)
    aus = r.stdout + r.stderr
    m = re.search(r"(\d+(?:\.\d+)?)%\s*der\s*\d+\s*Tintenpunkte", aus)
    if not m:
        m = re.search(r"(\d+(?:\.\d+)?)\s*%", aus)
    return float(m.group(1)) if m else None


def main():
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(BREITE), str(HOEHE)], check=True,
                   capture_output=True, text=True, timeout=60)
    t0 = time.time()
    while time.time() - t0 < 120 and "taskbar: start x=" not in s():
        time.sleep(0.3)
    pid = int(open(os.path.join(D, "pid")).read().strip())
    print("BOOT: %.1f s  (qemu %d)" % (time.time() - t0, pid))
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

    def probiere(befehl, marke):
        m.tippe(befehl)
        m.taste("ret")
        time.sleep(6.0)
        p = os.path.join(SHOTS, "%s.ppm" % marke)
        m.foto(p)
        lebt = True
        try:
            os.kill(pid, 0)
        except OSError:
            lebt = False
        print("\n>>> %-14s  QEMU %s" % (befehl, "laeuft" if lebt else "WEG"))
        if not lebt:
            return False, p
        for satz in ("nicht schreibbar", "init antwortet nicht",
                     "hat nicht abgeschaltet", "not found",
                     "command not found", "shutdown"):
            v = suche(p, satz)
            if v is not None and v >= 60:
                print("    im Bild: '%s' zu %.0f %%" % (satz, v))
        return True, p

    lebt, _ = probiere("shutdown", "01-shutdown")
    if lebt:
        lebt, _ = probiere("shutdown -f", "02-shutdown-f")
    if lebt:
        lebt, _ = probiere("ls /bin/shutdown", "03-ls")
    print("\nErgebnis: QEMU %s" % ("laeuft noch" if lebt else "beendet"))
    print("Abstuerze:", lesen.abstuerze(s()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
