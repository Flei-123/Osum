#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""ausschalten.py -- `shutdown` ueber die Oberflaeche, sauber gemessen.

    python3 ausschalten.py <name> <breite> <hoehe>

DER BEWEIS IST DER QEMU-PROZESS SELBST. Eine ACPI-Abschaltung beendet
die Maschine; mit `-no-reboot` kommt sie nicht zurueck. Ist der Prozess
weg, war es ein echtes Ausschalten und kein Bildschirmschoner.

Vorher wird im BILD nachgesehen, ob das getippte Wort ueberhaupt im
Terminal angekommen ist -- sonst misst man einen Tippfehler und nennt
ihn "Herunterfahren geht nicht". (Die Shell schreibt ins FENSTER, nicht
auf die serielle Leitung: kgui.fi:1765, SINK_WINDOW.)
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

NAME = sys.argv[1] if len(sys.argv) > 1 else "aus1"
BREITE = int(sys.argv[2]) if len(sys.argv) > 2 else 1280
HOEHE = int(sys.argv[3]) if len(sys.argv) > 3 else 800
D = os.path.join(HIER, "laeufe", NAME)
SHOTS = os.path.join(HIER, "shots", NAME)
os.makedirs(SHOTS, exist_ok=True)
SER = os.path.join(D, "serial.txt")
REPO = os.path.abspath(os.path.join(HIER, ".."))
MONO = os.path.join(REPO, "assets", "osum-mono.ttf")
SUCH = os.path.join(REPO, "tools", "usbimg", "searchtext.py")
RAND, TITEL = 2, 22


def s():
    return lesen.text(SER)


def suche(ppm, text, px=16):
    if not (ppm and os.path.exists(ppm)):
        return None
    r = subprocess.run(["python3", SUCH, ppm, MONO, str(px), text,
                        "--min", "50"], capture_output=True, text=True,
                       timeout=300)
    m = re.search(r"(\d+(?:\.\d+)?)\s*%", r.stdout + r.stderr)
    return float(m.group(1)) if m else None


def main():
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(BREITE), str(HOEHE)], check=True,
                   capture_output=True, text=True, timeout=60)
    t0 = time.time()
    while time.time() - t0 < 120 and "taskbar: start x=" not in s():
        time.sleep(0.3)
    print("BOOT: %.1f s" % (time.time() - t0))
    pid = int(open(os.path.join(D, "pid")).read().strip())
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
    if not term:
        print("kein Terminalfenster")
        return 1
    _i, tx, ty, tw, th = term
    print("Terminal id=%d (%d,%d) %dx%d" % term)

    # In den INHALT klicken, damit die Tastatur dort landet.
    m.klick_auf(tx + RAND + tw // 2, ty + TITEL + th // 2)
    time.sleep(1.5)

    # Erst pruefen, ob Tippen ueberhaupt ankommt.
    m.tippe("echo bereit")
    m.taste("ret")
    time.sleep(2.5)
    p = os.path.join(SHOTS, "01-bereit.ppm")
    m.foto(p)
    an = suche(p, "bereit")
    print("Tippen kommt an: 'bereit' zu %s %% im Bild" % an)

    # Und jetzt ausschalten.
    m.tippe("shutdown")
    m.taste("ret")
    weg = False
    t1 = time.time()
    for _ in range(60):
        time.sleep(1.0)
        try:
            os.kill(pid, 0)
        except OSError:
            weg = True
            break
    dauer = time.time() - t1

    txt = s()
    erg = {
        "tippen_kommt_an_prozent": an,
        "qemu_beendet": weg,
        "dauer_s": round(dauer, 1),
        "init_meldung": "shutdown" in txt or "poweroff" in txt.lower(),
        "abstuerze": lesen.abstuerze(txt),
    }
    print("\n7.4 Herunterfahren: %s (nach %.1f s)"
          % ("GEHT" if weg else "GEHT NICHT", dauer))
    print("    Abstuerze:", erg["abstuerze"])
    # Was der Kern zuletzt gesagt hat -- das ist der zweite Beleg.
    print("    letzte Zeilen:", repr(txt[-200:]))
    with open(os.path.join(D, "aus.json"), "w") as f:
        json.dump(erg, f, indent=1, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
