#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    shutdown.py -- `shutdown` over die Oberflaeche, clean gemessen.
    python3 shutdown.py <name> <width> <height>
"""
import json
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
from click_driver import Maschine
import read_all

NAME = sys.argv[1] if len(sys.argv) > 1 else "aus1"
WIDTH = int(sys.argv[2]) if len(sys.argv) > 2 else 1280
HEIGHT = int(sys.argv[3]) if len(sys.argv) > 3 else 800
D = os.path.join(HIER, "runs", NAME)
SHOTS = os.path.join(HIER, "shots", NAME)
os.makedirs(SHOTS, exist_ok=True)
SER = os.path.join(D, "serial.txt")
REPO = os.path.abspath(os.path.join(HIER, ".."))
MONO = os.path.join(REPO, "assets", "osum-mono.ttf")
SUCH = os.path.join(REPO, "tools", "usbimg", "searchtext.py")
RAND, TITLE = 2, 22


def s():
    return read_all.text(SER)


def lookup(ppm, text, px=16):
    if not (ppm and os.path.exists(ppm)):
        return None
    r = subprocess.run(["python3", SUCH, ppm, MONO, str(px), text,
                        "--min", "50"], capture_output=True, text=True,
                       timeout=300)
    m = re.search(r"(\d+(?:\.\d+)?)\s*%", r.stdout + r.stderr)
    return float(m.group(1)) if m else None


def main():
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(WIDTH), str(HEIGHT)], check=True,
                   capture_output=True, text=True, timeout=60)
    t0 = time.time()
    while time.time() - t0 < 120 and "taskbar: start x=" not in s():
        time.sleep(0.3)
    print("BOOT: %.1f s" % (time.time() - t0))
    pid = int(open(os.path.join(D, "pid")).read().strip())
    time.sleep(2.5)
    m = Maschine(os.path.join(D, "mon.sock"), WIDTH, HEIGHT)

    term = None
    bis = time.time() + 60
    while time.time() < bis and term is None:
        for i, lagen in read_all.window(s()).items():
            for x, y, w, h in lagen:
                if w == 560 and h == 380:
                    term = (i, x, y, w, h)
        if term is None:
            time.sleep(1.0)
    if not term:
        print("kein Terminalfenster")
        return 1
    _i, tx, ty, tw, th = term
    print("Terminal id=%d (%d,%d) %dx%d" % term)

    # In den INHALT klicken, damit die Tastatur dort landet.
    m.klick_auf(tx + RAND + tw // 2, ty + TITLE + th // 2)
    time.sleep(1.5)

    # Erst pruefen, ob Tippen ueberhaupt ankommt.
    m.tippe("echo bereit")
    m.key_press("ret")
    time.sleep(2.5)
    p = os.path.join(SHOTS, "01-bereit.ppm")
    m.photo(p)
    an = lookup(p, "bereit")
    print("Tippen kommt an: 'bereit' zu %s %% im Bild" % an)

    # Und jetzt ausschalten.
    m.tippe("shutdown")
    m.key_press("ret")
    gone = False
    t1 = time.time()
    for _ in range(60):
        time.sleep(1.0)
        try:
            os.kill(pid, 0)
        except OSError:
            gone = True
            break
    duration = time.time() - t1

    txt = s()
    erg = {
        "tippen_kommt_an_prozent": an,
        "qemu_beendet": gone,
        "dauer_s": round(duration, 1),
        "init_meldung": "shutdown" in txt or "poweroff" in txt.lower(),
        "abstuerze": read_all.abstuerze(txt),
    }
    print("\n7.4 Herunterfahren: %s (nach %.1f s)"
          % ("GEHT" if gone else "GEHT NICHT", duration))
    print("    Abstuerze:", erg["abstuerze"])
    # Was der Kern zuletzt gesagt hat -- das ist der zweite Beleg.
    print("    letzte Zeilen:", repr(txt[-200:]))
    with open(os.path.join(D, "aus.json"), "w") as f:
        json.dump(erg, f, indent=1, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
