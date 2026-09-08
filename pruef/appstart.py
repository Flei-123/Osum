#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""appstart.py -- JEDE App einzeln starten, in EINEM Lauf, und dabei
nach jedem Klick nachsehen, was der Starter wirklich gemacht hat.

    python3 appstart.py <name> <breite> <hoehe>

Der Unterschied zu durchklick2.py: hier wird nicht angenommen, dass das
Menue nach einem Programmstart noch offen ist. Nach JEDEM Start wird der
Zustand aus dem Fensterserver gelesen (`F_HIDDEN` des Starterfensters)
und erst dann entschieden, ob geklickt werden muss.
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
import lesen

NAME = sys.argv[1] if len(sys.argv) > 1 else "as1"
BREITE = int(sys.argv[2]) if len(sys.argv) > 2 else 1280
HOEHE = int(sys.argv[3]) if len(sys.argv) > 3 else 800
D = os.path.join(HIER, "laeufe", NAME)
SHOTS = os.path.join(HIER, "shots", NAME)
os.makedirs(SHOTS, exist_ok=True)
SER = os.path.join(D, "serial.txt")

# Womit sich jedes Programm meldet, wenn es wirklich angelaufen ist.
# Aus dem Quelltext geholt und nicht geraten:
#   kernel/user/explorer.fi   "explorer: ready"
#   kernel/user/edit.fi:1394  "edit: ready"
#   kernel/user/settings.fi:2683 "settings: ready w="
#   kernel/user/widgetdemo.fi:127 "widgetdemo: ready"
#   kernel/user/launcher.fi   "launcher: ready"
#   kernel/user/sh.fi:113     "sh: ready, osum"
MARKE = {
    "Datei-Explorer": "explorer: ready",
    "Editor": "edit: ready",
    "Einstellungen": "settings: ready",
    "Suchen": "launcher: ready",
    "Terminal": "sh: ready",
    "Widgets": "widgetdemo: ready",
}


def s():
    return lesen.text(SER)


def start_qemu():
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(BREITE), str(HOEHE)], check=True,
                   capture_output=True, text=True, timeout=60)
    t0 = time.time()
    while time.time() - t0 < 120:
        # NICHT auf "taskbar: STEHT" warten: die Zeile kommt genau
        # EINMAL und kann im Gedraenge auf der Leitung zerrissen werden
        # (gemessen: in einem Lauf 0 Treffer, obwohl die Leiste stand).
        # "taskbar: start x=" schreibt sie bei JEDEM Anstrich neu --
        # was einmal vorkommt, ist eine Hoffnung; was 120-mal vorkommt,
        # ist eine Messung.
        if "taskbar: start x=" in s():
            return time.time() - t0
        time.sleep(0.3)
    return None


def menue_zustand(txt):
    """auf / zu -- aus den Meldungen der Leiste, die seit TUERSCHLOSS
    die Richtung sagen. Der letzte Ausschlag gilt."""
    a = txt.rfind("startmenue auf")
    z = txt.rfind("startmenue zu")
    if a < 0 and z < 0:
        return "unbekannt"
    return "auf" if a > z else "zu"


def main():
    boot = start_qemu()
    print("BOOT: %s s" % (round(boot, 1) if boot else "FEHLT"))
    if not boot:
        return 1
    time.sleep(2.5)

    m = Maschine(os.path.join(D, "mon.sock"), BREITE, HOEHE)

    # Das Starterfenster taucht in der Liste des Servers erst auf, wenn
    # es einmal gezeigt wurde. Also erst aufmachen, dann die Lage holen
    # -- sonst steht `starter_fenster` auf None und der Lauf bricht ab,
    # obwohl alles in Ordnung ist.
    for _ in range(3):
        if lesen.starter_fenster(s()):
            break
        m.klick_auf(18, HOEHE - 20)
        time.sleep(2.0)

    txt = s()
    sf = lesen.starter_fenster(txt)
    lr = lesen.geom(txt, "launcher: rect id=2 kind=5 ")
    zh = re.findall(r"launcher: rows x=\d+ base=\d+ zh=(\d+)", txt)
    eintraege = lesen.apps(txt)
    tr, ap = lesen.app_zahl(txt)
    print("Starter zaehlt apps=%d treffer=%d" % (ap, tr))
    if not sf or not lr:
        print("keine Lage: sf=%s lr=%s" % (sf, lr))
        return 1
    _id, gx, gy = sf
    lx, ly = lr[-1][0], lr[-1][1]
    z = int(zh[-1]) if zh else 20
    print("Starter id=%d bei (%d,%d), Liste (%d,%d), zh=%d"
          % (_id, gx, gy, lx, ly, z))
    for i in sorted(eintraege):
        print("   i=%d %-16s %s" % (i, eintraege[i][0], eintraege[i][1]))

    ergebnis = {}
    for i in sorted(eintraege):
        name, exe = eintraege[i]
        marke = MARKE.get(name)
        vor = s().count(marke) if marke else 0

        # Das Menue in einen BEKANNTEN Zustand bringen: solange klicken,
        # bis die Leiste 'auf' sagt (hoechstens dreimal).
        for _ in range(3):
            if menue_zustand(s()) == "auf":
                break
            m.klick_auf(18, HOEHE - 20)
            time.sleep(1.6)
        zustand = menue_zustand(s())

        zx = gx + lx + 60
        zy = gy + ly + 2 + i * z + z // 2
        m.klick_auf(zx, zy)
        time.sleep(5.0)
        txt = s()
        nach = txt.count(marke) if marke else 0
        gestartet = nach > vor
        ergebnis[name] = {"i": i, "exec": exe, "marke": marke,
                          "vorher": vor, "nachher": nach,
                          "menue_war": zustand, "gestartet": gestartet}
        print("%-16s i=%d  Menue %-3s  '%s' %d -> %d   %s"
              % (name, i, zustand, marke, vor, nach,
                 "GESTARTET" if gestartet else "nichts"))
        m.foto(os.path.join(SHOTS, "app-%d-%s.png"
                            % (i, re.sub(r"\W", "", name))))

    with open(os.path.join(D, "appstart.json"), "w") as f:
        json.dump(ergebnis, f, indent=1, ensure_ascii=False)
    n = sum(1 for v in ergebnis.values() if v["gestartet"])
    print("\n%d von %d Programmen gestartet" % (n, len(ergebnis)))
    print("Abstuerze:", lesen.abstuerze(s()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
