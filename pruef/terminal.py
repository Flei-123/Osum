#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    terminal.py -- im Terminal WIRKLICH arbeiten, und es im image messen.
    python3 terminal.py <name> <width> <height>
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

NAME = sys.argv[1] if len(sys.argv) > 1 else "t1"
WIDTH = int(sys.argv[2]) if len(sys.argv) > 2 else 1280
HEIGHT = int(sys.argv[3]) if len(sys.argv) > 3 else 800
D = os.path.join(HIER, "laeufe", NAME)
SHOTS = os.path.join(HIER, "shots", NAME)
os.makedirs(SHOTS, exist_ok=True)
SER = os.path.join(D, "serial.txt")
REPO = os.path.abspath(os.path.join(HIER, ".."))
MONO = os.path.join(REPO, "assets", "osum-mono.ttf")
SUCH = os.path.join(REPO, "tools", "usbimg", "searchtext.py")
ERG = {}


def s():
    return read_all.text(SER)


def merke(nr, was, erg, beleg=""):
    ERG[nr] = {"was": was, "ergebnis": erg, "beleg": str(beleg)[:300]}
    print("%-5s %-40s %-12s %s" % (nr, was[:40], erg, str(beleg)[:70]))


def photo_ppm(m, n):
    """PPM behalten -- searchtext.py liest PPM."""
    p = os.path.join(SHOTS, "%s.ppm" % n)
    return m.photo(p)


def lookup(ppm, text, px=16, mind=60.0):
    """Wie viel Prozent der Tintenpunkte dieser Zeile im Bild stehen."""
    if not (os.path.exists(SUCH) and os.path.exists(MONO) and ppm
            and os.path.exists(ppm)):
        return None
    try:
        r = subprocess.run(["python3", SUCH, ppm, MONO, str(px), text,
                            "--min", str(mind)],
                           capture_output=True, text=True, timeout=300)
        m = re.search(r"(\d+(?:\.\d+)?)\s*%", r.stdout + r.stderr)
        return float(m.group(1)) if m else None
    except Exception as e:
        print("   suchtext: %s" % e)
        return None


def main():
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(WIDTH), str(HEIGHT)], check=True,
                   capture_output=True, text=True, timeout=60)
    t0 = time.time()
    while time.time() - t0 < 120 and "taskbar: start x=" not in s():
        time.sleep(0.3)
    print("BOOT: %.1f s\n" % (time.time() - t0))
    time.sleep(2.5)
    m = Maschine(os.path.join(D, "mon.sock"), WIDTH, HEIGHT)

    # DAS TERMINALFENSTER DES KERNS steht schon: `wmshell` startet
    # /bin/sh darin (id=7, 560x380 bei 24,40). Es muss nur den Fokus
    # bekommen -- ein Klick hinein.
    #
    # ABER: der Fensterserver berichtet seine Liste (`wm: fen i=..`) nur
    # ab und zu. Kurz nach dem Hochfahren steht dort nur der Knopf der
    # Leiste. Also wird gewartet, bis die Lage wirklich gemeldet wurde,
    # statt sie beim ersten Blick zu verlangen.
    term = None
    bis = time.time() + 60
    while time.time() < bis and term is None:
        f = read_all.window(s())
        for i, lagen in f.items():
            for x, y, w, h in lagen:
                if w == 560 and h == 380:
                    term = (i, x, y, w, h)
        if term is None:
            time.sleep(1.0)
    if not term:
        merke("3.6", "Terminalfenster vorhanden", "GEHT NICHT", "kein 560x380")
        return finish()
    i, tx, ty, tw, th = term
    merke("3.6", "Terminalfenster vorhanden", "GEHT",
          "id=%d bei (%d,%d) %dx%d" % (i, tx, ty, tw, th))

    m.klick_auf(tx + tw // 2, ty + th // 2)
    time.sleep(1.2)
    vor = photo_ppm(m, "01-terminal-leer")

    # ---------------------------------------------- 6.2 deutsche Belegung
    # `z` liegt auf deutscher und US-Belegung an VERSCHIEDENEN Orten.
    # Der Monitor schickt die POSITION der Taste (US-Namen), das System
    # legt sie aus. Getippt wird die Taste, die auf US `y` heisst: auf
    # deutscher Belegung kommt dabei `z` heraus.
    m.tippe("echo dezimal")
    m.key_press("ret")
    time.sleep(2.5)
    b1 = photo_ppm(m, "02-echo-dezimal")
    p_de = lookup(b1, "dezimal")
    merke("6.2", "deutsche Belegung wirkt (z bleibt z)",
          "GEHT" if p_de and p_de >= 60 else "GEHT NICHT",
          "'dezimal' zu %s %% im Bild" % p_de)

    # ---------------------------------------------- 6.3 Umlaute
    m.tippe("echo Grüße")
    m.key_press("ret")
    time.sleep(2.5)
    b2 = photo_ppm(m, "03-echo-umlaut")
    p_um = lookup(b2, "Grüße")
    merke("6.3", "Umlaute tippbar (Grüße)",
          "GEHT" if p_um and p_um >= 60 else "GEHT NICHT",
          "'Grüße' zu %s %% im Bild" % p_um)

    # ---------------------------------------------- 3.6 ls gibt Ausgabe
    m.tippe("ls /bin")
    m.key_press("ret")
    time.sleep(3.5)
    b3 = photo_ppm(m, "04-ls-bin")
    p_ls = lookup(b3, "firnc")
    merke("8.1", "firnc liegt im Abbild (ls /bin)",
          "GEHT" if p_ls and p_ls >= 60 else "GEHT NICHT",
          "'firnc' zu %s %% im Bild" % p_ls)

    # ---------------------------------------------- 8.2 Selbst-Hosting
    # Eine Quelle schreiben, uebersetzen, binden, ausfuehren.
    for row in ('echo "fn main() -> i32 { return 42 }" > /tmp/h.fi',
                  "firnc /tmp/h.fi -o /tmp/h.s",
                  "fas /tmp/h.s -o /tmp/h",
                  "/tmp/h",
                  "echo LAUF=$?"):
        m.tippe(row)
        m.key_press("ret")
        time.sleep(4.0)
    b4 = photo_ppm(m, "05-selbsthosting")
    p_lauf = lookup(b4, "LAUF=42")
    merke("8.2", "auf dem Stick uebersetzen und ausfuehren",
          "GEHT" if p_lauf and p_lauf >= 60 else "GEHT NICHT",
          "'LAUF=42' zu %s %% im Bild" % p_lauf)

    merke("7.5", "keine Abstuerze",
          "GEHT" if read_all.abstuerze(s()) == 0 else "GEHT NICHT",
          "%d Treffer" % read_all.abstuerze(s()))
    return finish()


def finish():
    with open(os.path.join(D, "terminal.json"), "w") as f:
        json.dump(ERG, f, indent=1, ensure_ascii=False)
    print("\n-> %s/terminal.json" % D)
    return 0


if __name__ == "__main__":
    sys.exit(main())
