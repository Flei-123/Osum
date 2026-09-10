#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""probe2.py -- einen App-Eintrag im Starter WIRKLICH treffen.

Der Ort kommt aus den eigenen Meldungen des Starters und ist damit
gerechnet und nicht geraten:

    launcher: geom x=<gx> y=<gy> w=.. h=..     das Fenster
    launcher: rows x=.. base=<b> zh=<z> ..     die Zeilen der Liste

Die i-te Zeile hat ihre Grundlinie bei `base + i*zh` IM FENSTER; ein
Klick gehoert etwa vier Bildpunkte darueber in die Mitte der Zeile.
"""
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from klick import Maschine

HIER = os.path.dirname(os.path.abspath(__file__))
NAME = sys.argv[1] if len(sys.argv) > 1 else "p2"
BREITE = int(sys.argv[2]) if len(sys.argv) > 2 else 1280
HOEHE = int(sys.argv[3]) if len(sys.argv) > 3 else 800
ZEILE = int(sys.argv[4]) if len(sys.argv) > 4 else 0
D = os.path.join(HIER, "laeufe", NAME)
SHOTS = os.path.join(HIER, "shots")
os.makedirs(SHOTS, exist_ok=True)


def serial():
    p = os.path.join(D, "serial.txt")
    return open(p, encoding="utf-8", errors="replace").read() if os.path.exists(p) else ""


def main():
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(BREITE), str(HOEHE)], check=True,
                   capture_output=True, text=True, timeout=60)
    t0 = time.time()
    bis = time.time() + 90
    while time.time() < bis:
        if "taskbar: STEHT" in serial():
            break
        time.sleep(0.5)
    print("BOOT: %.1f s" % (time.time() - t0))

    m = Maschine(os.path.join(D, "mon.sock"), BREITE, HOEHE)
    m.foto(os.path.join(SHOTS, "%s-01-schreibtisch.png" % NAME))

    # Startmenue auf
    m.klick_auf(18, HOEHE - 20)
    time.sleep(2.5)
    m.foto(os.path.join(SHOTS, "%s-02-startmenue.png" % NAME))

    s = serial()
    geom = re.findall(r"launcher: geom x=(\d+) y=(\d+) w=(\d+) h=(\S+)", s)
    rows = re.findall(r"launcher: rows x=(\d+) base=(\d+) zh=(\d+)", s)
    if not geom or not rows:
        print("KEINE GEOMETRIE -- Starter hat sich nicht gemeldet")
        return 1
    gx, gy = int(geom[-1][0]), int(geom[-1][1])
    rx, base, zh = (int(v) for v in rows[-1])
    treffer = re.findall(r"launcher: treffer i=(\d+) name=\[([^\]]*)\] exec=\[([^\]]*)\]", s)
    print("Starterfenster bei x=%d y=%d, Zeilen base=%d zh=%d" % (gx, gy, base, zh))
    for i, n, e in treffer:
        print("   i=%s %-16s %s" % (i, n, e))

    ziel = [t for t in treffer if int(t[0]) == ZEILE]
    if not ziel:
        print("Zeile %d gibt es nicht" % ZEILE)
        return 1
    name, exe = ziel[0][1], ziel[0][2]

    # Die Grundlinie der Zeile im Fenster -> Ort auf dem Schirm.
    # Mitte der Zeile: base + i*zh - zh/3 ist innerhalb der Zeile.
    zy = gy + base + ZEILE * zh - zh // 3
    zx = gx + rx + 60
    print("Klick auf [%s] -> %s   bei (%d,%d)" % (name, exe, zx, zy))

    vor = serial()
    m.klick_auf(zx, zy)
    time.sleep(4.0)
    m.foto(os.path.join(SHOTS, "%s-03-nach-start.png" % NAME))

    s = serial()
    neu = s[len(vor):]
    starts = re.findall(r"launcher: start (\S+) pid=(-?\d+)", s)
    print("\nLAUNCHER-STARTS insgesamt:", starts)
    gut = [x for x in starts if not x[1].startswith("-") and x[1] != "0"]
    print("  pid>0: %d   negativ: %d" % (len(gut),
          len([x for x in starts if x[1].startswith("-")])))

    # Ist ein Fenster dazugekommen? elf: start sagt, dass wirklich
    # geladen wurde.
    elfs = re.findall(r"elf: start (\S+)", s)
    print("ELF-Ladungen:", elfs[-6:])
    print("Shell: ready=%d bye=%d" % (len(re.findall(r"sh: ready", s)),
                                      len(re.findall(r"sh: bye", s))))
    print("Panik:", len(re.findall(r"PANIK|#PF|#UD", s)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
