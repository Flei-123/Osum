#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""probe4.py -- eine App aus dem Starter WIRKLICH starten.

Zwei Dinge, die die Vorlaeufer gelernt haben und die hier drinstehen:

1. DER STARTER LAEUFT SCHON. `desk_start` startet ihn beim Hochfahren
   (`desk: start /bin/launcher pid=8`), sein Fenster ist nur
   zugeklappt. Seit Runde TUERSCHLOSS findet die Leiste es wieder --
   der erste Klick auf Start macht es also ZU und der zweite AUF.
   Deshalb wird hier gezaehlt und nicht geraten: geklickt wird, bis
   die Liste im Bild steht.

2. DIE LAGE KOMMT AUS `launcher: geom`, und die sagt seit derselben
   Runde die Wahrheit (vorher standen dort die toten Festwerte
   190/110, waehrend das Fenster bei 8/452 stand).
"""
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from klick import Maschine

HIER = os.path.dirname(os.path.abspath(__file__))
NAME = sys.argv[1] if len(sys.argv) > 1 else "p4"
BREITE = int(sys.argv[2]) if len(sys.argv) > 2 else 1280
HOEHE = int(sys.argv[3]) if len(sys.argv) > 3 else 800
ZEILE = int(sys.argv[4]) if len(sys.argv) > 4 else 0
D = os.path.join(HIER, "laeufe", NAME)
SHOTS = os.path.join(HIER, "shots")
os.makedirs(SHOTS, exist_ok=True)

# Die serielle Leitung wird von mehreren Prozessen beschrieben; Zeilen
# koennen ineinander laufen. Darum werden die Zahlen mit Suchmustern
# geholt, die auch dann noch greifen (kein ^...$).
RE_GEOM = re.compile(r"launcher: geom x=(\d+) y=(\d+) w=(\d+)")
RE_LIST = re.compile(r"launcher: rect id=2 kind=5 x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
RE_ROWS = re.compile(r"launcher: rows x=(\d+) base=(\d+) zh=(\d+)")
RE_TREF = re.compile(r"launcher: treffer i=(\d+) name=\[([^\]]*)\] exec=\[([^\]]*)\]")
RE_START = re.compile(r"launcher: start (\S+)\s+pid=(-?\d+)")


def serial():
    p = os.path.join(D, "serial.txt")
    return open(p, encoding="utf-8", errors="replace").read() if os.path.exists(p) else ""


def start_qemu():
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(BREITE), str(HOEHE)], check=True,
                   capture_output=True, text=True, timeout=60)
    bis = time.time() + 90
    t0 = time.time()
    while time.time() < bis:
        if "taskbar: STEHT" in serial():
            return time.time() - t0
        time.sleep(0.5)
    return None


def menue_auf(m, versuche=3):
    """Auf den Startknopf klicken, bis das Menue OFFEN ist.

    Offen heisst: die Leiste hat NICHT gerade 'startmenue zu' gesagt
    und der Starter hat seine Liste neu gemeldet."""
    for i in range(versuche):
        vor = serial()
        zu_vor = vor.count("startmenue zu")
        m.klick_auf(18, HOEHE - 20)
        time.sleep(2.5)
        s = serial()
        if s.count("startmenue zu") > zu_vor:
            print("   Klick %d: Menue war offen -> zugeklappt" % (i + 1))
            continue
        print("   Klick %d: Menue aufgeklappt" % (i + 1))
        return True
    return False


def main():
    b = start_qemu()
    print("BOOT: %s s" % (round(b, 1) if b else "KEIN SCHREIBTISCH"))
    if b is None:
        return 1

    m = Maschine(os.path.join(D, "mon.sock"), BREITE, HOEHE)
    m.foto(os.path.join(SHOTS, "%s-01-schreibtisch.png" % NAME))

    if not menue_auf(m):
        print("Menue geht nicht auf")
        return 1
    m.foto(os.path.join(SHOTS, "%s-02-menue.png" % NAME))

    s = serial()
    geom, lst, rows = RE_GEOM.findall(s), RE_LIST.findall(s), RE_ROWS.findall(s)
    if not (geom and lst and rows):
        print("KEINE GEOMETRIE  geom=%d rect=%d rows=%d"
              % (len(geom), len(lst), len(rows)))
        return 1
    gx, gy = int(geom[-1][0]), int(geom[-1][1])
    lx, ly, lw, lh = (int(v) for v in lst[-1])
    zh = int(rows[-1][2])
    eintraege = {int(i): (n, e) for i, n, e in RE_TREF.findall(s)}
    print("Fenster (%d,%d)  Liste (%d,%d) %dx%d  zh=%d"
          % (gx, gy, lx, ly, lw, lh, zh))
    for i in sorted(eintraege):
        print("   i=%d %-16s %s" % (i, eintraege[i][0], eintraege[i][1]))
    if ZEILE not in eintraege:
        print("Zeile %d gibt es nicht" % ZEILE)
        return 1
    name, exe = eintraege[ZEILE]

    zx = gx + lx + 60
    zy = gy + ly + 2 + ZEILE * zh + zh // 2
    print("\nKlick auf [%s] -> %s   bei (%d,%d)" % (name, exe, zx, zy))
    vor_bild = os.path.join(SHOTS, "%s-03-vor-start.png" % NAME)
    m.foto(vor_bild)
    m.klick_auf(zx, zy)
    time.sleep(5.0)
    nach_bild = os.path.join(SHOTS, "%s-04-nach-start.png" % NAME)
    m.foto(nach_bild)

    s = serial()
    starts = RE_START.findall(s)
    gut = [x for x in starts if not x[1].startswith("-") and x[1] != "0"]
    schlecht = [x for x in starts if x[1].startswith("-")]
    print("\nLAUNCHER-STARTS:", starts)
    print("  pid>0: %d   negativ: %d" % (len(gut), len(schlecht)))
    print("Shell: ready=%d bye=%d" % (s.count("sh: ready"), s.count("sh: bye")))
    print("Panik:", len(re.findall(r"PANIK|#PF|#UD", s)))

    # Bildpunkt-Unterschied: ist wirklich ein Fenster aufgegangen?
    try:
        r = subprocess.run(["python3", os.path.join(HIER, "sicht.py"),
                            "vergleiche", vor_bild, nach_bild],
                           capture_output=True, text=True, timeout=120)
        print("BILD:", r.stdout.strip().splitlines()[-1] if r.stdout.strip() else r.stderr[:200])
    except Exception as e:
        print("BILD: kein Vergleich (%s)" % e)
    return 0 if gut else 2


if __name__ == "__main__":
    sys.exit(main())
