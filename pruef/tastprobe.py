#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tastprobe.py -- KOMMT UEBERHAUPT EINE TASTE AN?

    python3 tastprobe.py [name] [breite] [hoehe]

Die kleinste Messung, die den Fund dieser Runde festhaelt: mit
`-device usb-ehci` meldet der Kern `usb: no controller` und auf der
ganzen seriellen Leitung steht keine einzige Zeile ueber eine Taste.
Mit `-device qemu-xhci` wird die Tastatur aufgezaehlt.

Geprueft werden vier Dinge, jedes mit seiner eigenen Zeile auf der
Leitung -- und in DIESER Reihenfolge, weil jede spaetere die frueheren
voraussetzt:

    1. usb:  ein Wirtstreiber ist da        (kein "no controller")
    2. hid:  eine Tastatur wurde gefunden
    3. key:  ein Buchstabe kommt durch      (kbd.deliver)
    4. taskbar: klinke / wm: fokus          -- die Kuerzel wirken
"""
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
from klick import Maschine

NAME = sys.argv[1] if len(sys.argv) > 1 else "tast"
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


def main():
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(BREITE), str(HOEHE)], check=True,
                   capture_output=True, text=True, timeout=60)
    t0 = time.time()
    while time.time() - t0 < 150:
        if "taskbar: start x=" in s():
            break
        time.sleep(0.3)
    print("hochgefahren nach %.1f s" % (time.time() - t0))
    time.sleep(3)

    m = Maschine(os.path.join(D, "mon.sock"), BREITE, HOEHE)

    # 1./2. Was sagt der USB-Teil?
    t = s()
    kein = "usb: no controller" in t
    print("1. usb: no controller     : %s" % ("JA (schlecht)" if kein
                                              else "nein (gut)"))
    for z in re.findall(r"usb: [^\n]{0,70}", t)[:6]:
        print("     |", z)
    for z in re.findall(r"hid[a-z]*: [^\n]{0,70}", t)[:6]:
        print("     |", z)

    # 3. Ein Buchstabe.
    vor_key = len(re.findall(r"key: ", t))
    m.klick_auf(BREITE // 2, HOEHE // 2)
    time.sleep(0.6)
    m.tippe("echo hallo")
    time.sleep(1.5)
    t = s()
    nach_key = len(re.findall(r"key: ", t))
    print("3. key:-Zeilen            : %d -> %d" % (vor_key, nach_key))

    # ZUERST EIN ZWEITES FENSTER, sonst ist Alt+Tab folgenlos -- und
    # zwar zu Recht. Gemessen im Lauf davor: von fuenf Fenstern ist
    # genau EINES umschaltbar (id=7, das Terminal, lay=1 fl=0); der
    # Schreibtisch ist lay=0, Leiste und Startmenue sind lay=2, und der
    # Starter id=10 traegt fl=3 = F_HIDDEN|F_NODECO. Ein Alt+Tab, das
    # bei einem einzigen Fenster nichts tut, ist kein Fehler.
    # Also: Startmenue auf, Editor starten, DANN messen.
    m.klick_auf(18, HOEHE - 20)
    time.sleep(2.0)
    t = s()
    mm = re.search(r"wm: fen i=\d+ id=(\d+) x=(\d+) y=(\d+) w=(\d+) "
                   r"h=(\d+) lay=2 fl=2", t)
    # der zweite Eintrag im Menue ist der Editor
    for zeile in re.findall(r"wm: fen i=\d+ id=\d+ x=(\d+) y=(\d+) "
                            r"w=440 h=300 lay=2", t)[-1:]:
        mx, my = int(zeile[0]), int(zeile[1])
        m.klick_auf(mx + 60, my + 2 + 1 * 20 + 10)
        time.sleep(5.0)
    t = s()
    fen = re.findall(r"wm: fen i=\d+ id=(\d+) [^\n]*lay=1 fl=0", t)
    print("   umschaltbare Fenster (lay=1 fl=0): %s" % sorted(set(fen)))

    # 4. Die Kuerzel: Super allein und Alt+Tab.
    vor_hk = len(re.findall(r"taskbar: klinke", t))
    vor_fok = len(re.findall(r"wm: fokus", t))
    m.taste("meta_l")
    time.sleep(2.0)
    m.sag("sendkey alt-tab", 0.2)
    time.sleep(1.5)
    m.sag("sendkey alt-tab", 0.2)
    time.sleep(2.0)
    t = s()
    print("4. taskbar: klinke        : %d -> %d"
          % (vor_hk, len(re.findall(r"taskbar: klinke", t))))
    print("   wm: fokus              : %d -> %d"
          % (vor_fok, len(re.findall(r"wm: fokus", t))))
    for z in re.findall(r"wm: fokus id=\d+ vor=\d+", t)[-6:]:
        print("     |", z)
    for z in re.findall(r"taskbar: startmenue \w+", t)[-4:]:
        print("     |", z)

    m.sag("quit", 0.2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
