#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    probe3.py -- App starten, Ort aus dem LISTENRECHTECK gerechnet.
"""
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from click_driver import Maschine

HIER = os.path.dirname(os.path.abspath(__file__))
NAME = sys.argv[1] if len(sys.argv) > 1 else "p3"
WIDTH = int(sys.argv[2]) if len(sys.argv) > 2 else 1280
HEIGHT = int(sys.argv[3]) if len(sys.argv) > 3 else 800
ROW = int(sys.argv[4]) if len(sys.argv) > 4 else 0
D = os.path.join(HIER, "runs", NAME)
SHOTS = os.path.join(HIER, "shots")
os.makedirs(SHOTS, exist_ok=True)


def serial():
    p = os.path.join(D, "serial.txt")
    return open(p, encoding="utf-8", errors="replace").read() if os.path.exists(p) else ""


def geometrie(s):
    """Fenster, Liste und Zeilenhoehe aus den Meldungen."""
    geom = re.findall(r"launcher: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)", s)
    lst = re.findall(r"launcher: rect id=2 kind=5 x=(\d+) y=(\d+) w=(\d+) h=(\d+)", s)
    rows = re.findall(r"launcher: rows x=(\d+) base=(\d+) zh=(\d+)", s)
    if not geom or not lst or not rows:
        return None
    gx, gy = int(geom[-1][0]), int(geom[-1][1])
    lx, ly, lw, lh = (int(v) for v in lst[-1])
    zh = int(rows[-1][2])
    return gx, gy, lx, ly, lw, lh, zh


def main():
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(WIDTH), str(HEIGHT)], check=True,
                   capture_output=True, text=True, timeout=60)
    bis = time.time() + 90
    t0 = time.time()
    while time.time() < bis:
        if "taskbar: STEHT" in serial():
            break
        time.sleep(0.5)
    print("BOOT: %.1f s" % (time.time() - t0))

    m = Maschine(os.path.join(D, "mon.sock"), WIDTH, HEIGHT)
    m.klick_auf(18, HEIGHT - 20)          # Startmenue auf
    time.sleep(2.5)
    m.photo(os.path.join(SHOTS, "%s-01-menue.png" % NAME))

    s = serial()
    g = geometrie(s)
    if not g:
        print("KEINE GEOMETRIE")
        return 1
    gx, gy, lx, ly, lw, lh, zh = g
    treffer = re.findall(r"launcher: treffer i=(\d+) name=\[([^\]]*)\] exec=\[([^\]]*)\]", s)
    eintraege = {}
    for i, n, e in treffer:
        eintraege[int(i)] = (n, e)
    print("Fenster (%d,%d)  Liste (%d,%d) %dx%d  zh=%d"
          % (gx, gy, lx, ly, lw, lh, zh))
    for i in sorted(eintraege):
        print("   i=%d %-16s %s" % (i, eintraege[i][0], eintraege[i][1]))

    if ROW not in eintraege:
        print("Zeile %d gibt es nicht" % ROW)
        return 1
    name, exe = eintraege[ROW]

    zx = gx + lx + 60
    zy = gy + ly + 2 + ROW * zh + zh // 2
    print("\nKlick auf [%s] -> %s   bei (%d,%d)" % (name, exe, zx, zy))

    m.klick_auf(zx, zy)
    time.sleep(4.5)
    m.photo(os.path.join(SHOTS, "%s-02-nach-start.png" % NAME))

    s = serial()
    starts = re.findall(r"launcher: start (\S+) pid=(-?\d+)", s)
    print("\nLAUNCHER-STARTS:", starts)
    gut = [x for x in starts if not x[1].startswith("-") and x[1] != "0"]
    bad = [x for x in starts if x[1].startswith("-")]
    print("  pid>0: %d   negativ: %d" % (len(gut), len(bad)))
    print("ELF:", re.findall(r"elf: start (\S+)", s)[-8:])
    print("Shell: ready=%d bye=%d" % (len(re.findall(r"sh: ready", s)),
                                      len(re.findall(r"sh: bye", s))))
    print("Panik:", len(re.findall(r"PANIK|#PF|#UD", s)))
    return 0 if gut else 2


if __name__ == "__main__":
    sys.exit(main())
