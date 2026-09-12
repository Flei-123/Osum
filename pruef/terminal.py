#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""terminal.py -- im Terminal WIRKLICH arbeiten, und es im BILD messen.

    python3 terminal.py <name> <breite> <hoehe>

WARUM IM BILD UND NICHT AUF DER LEITUNG. Das Terminalfenster des Kerns
haengt am Konsolen-TTY, und dessen Senke ist SINK_WINDOW
(`kgui.fi:1765`): was die Shell schreibt, geht ins FENSTER und nicht auf
die serielle Leitung. Wer dort nach der Ausgabe sucht, findet nichts und
haelt eine funktionierende Shell fuer tot -- genau der Fehlschluss, der
in dieser Runde einmal gemacht wurde.

Gemessen wird darum mit `tools/usbimg/searchtext.py`: es rastert eine
Zeile mit einer ZWEITEN Fassung des Rasterers (tools/ttf/raster.py, in
Python) und sucht ihre Tintenpunkte im Foto. Prozent = wie viel davon
wirklich im Bild steht.
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

NAME = sys.argv[1] if len(sys.argv) > 1 else "t1"
BREITE = int(sys.argv[2]) if len(sys.argv) > 2 else 1280
HOEHE = int(sys.argv[3]) if len(sys.argv) > 3 else 800
D = os.path.join(HIER, "laeufe", NAME)
SHOTS = os.path.join(HIER, "shots", NAME)
os.makedirs(SHOTS, exist_ok=True)
SER = os.path.join(D, "serial.txt")
REPO = os.path.abspath(os.path.join(HIER, ".."))
MONO = os.path.join(REPO, "assets", "osum-mono.ttf")
SUCH = os.path.join(REPO, "tools", "usbimg", "searchtext.py")
ERG = {}


def s():
    return lesen.text(SER)


def merke(nr, was, erg, beleg=""):
    ERG[nr] = {"was": was, "ergebnis": erg, "beleg": str(beleg)[:300]}
    print("%-5s %-40s %-12s %s" % (nr, was[:40], erg, str(beleg)[:70]))


def foto_ppm(m, n):
    """PPM behalten -- searchtext.py liest PPM."""
    p = os.path.join(SHOTS, "%s.ppm" % n)
    return m.foto(p)


def suche(ppm, text, px=16, mind=60.0):
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
                    str(BREITE), str(HOEHE)], check=True,
                   capture_output=True, text=True, timeout=60)
    t0 = time.time()
    while time.time() - t0 < 120 and "taskbar: start x=" not in s():
        time.sleep(0.3)
    print("BOOT: %.1f s\n" % (time.time() - t0))
    time.sleep(2.5)
    m = Maschine(os.path.join(D, "mon.sock"), BREITE, HOEHE)

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
        f = lesen.fenster(s())
        for i, lagen in f.items():
            for x, y, w, h in lagen:
                if w == 560 and h == 380:
                    term = (i, x, y, w, h)
        if term is None:
            time.sleep(1.0)
    if not term:
        merke("3.6", "Terminalfenster vorhanden", "GEHT NICHT", "kein 560x380")
        return schluss()
    i, tx, ty, tw, th = term
    merke("3.6", "Terminalfenster vorhanden", "GEHT",
          "id=%d bei (%d,%d) %dx%d" % (i, tx, ty, tw, th))

    m.klick_auf(tx + tw // 2, ty + th // 2)
    time.sleep(1.2)
    vor = foto_ppm(m, "01-terminal-leer")

    # ---------------------------------------------- 6.2 deutsche Belegung
    # `z` liegt auf deutscher und US-Belegung an VERSCHIEDENEN Orten.
    # Der Monitor schickt die POSITION der Taste (US-Namen), das System
    # legt sie aus. Getippt wird die Taste, die auf US `y` heisst: auf
    # deutscher Belegung kommt dabei `z` heraus.
    m.tippe("echo dezimal")
    m.taste("ret")
    time.sleep(2.5)
    b1 = foto_ppm(m, "02-echo-dezimal")
    p_de = suche(b1, "dezimal")
    merke("6.2", "deutsche Belegung wirkt (z bleibt z)",
          "GEHT" if p_de and p_de >= 60 else "GEHT NICHT",
          "'dezimal' zu %s %% im Bild" % p_de)

    # ---------------------------------------------- 6.3 Umlaute
    m.tippe("echo Grüße")
    m.taste("ret")
    time.sleep(2.5)
    b2 = foto_ppm(m, "03-echo-umlaut")
    p_um = suche(b2, "Grüße")
    merke("6.3", "Umlaute tippbar (Grüße)",
          "GEHT" if p_um and p_um >= 60 else "GEHT NICHT",
          "'Grüße' zu %s %% im Bild" % p_um)

    # ---------------------------------------------- 3.6 ls gibt Ausgabe
    m.tippe("ls /bin")
    m.taste("ret")
    time.sleep(3.5)
    b3 = foto_ppm(m, "04-ls-bin")
    p_ls = suche(b3, "firnc")
    merke("8.1", "firnc liegt im Abbild (ls /bin)",
          "GEHT" if p_ls and p_ls >= 60 else "GEHT NICHT",
          "'firnc' zu %s %% im Bild" % p_ls)

    # ---------------------------------------------- 8.2 Selbst-Hosting
    # Eine Quelle schreiben, uebersetzen, binden, ausfuehren.
    for zeile in ('echo "fn main() -> i32 { return 42 }" > /tmp/h.fi',
                  "firnc /tmp/h.fi -o /tmp/h.s",
                  "fas /tmp/h.s -o /tmp/h",
                  "/tmp/h",
                  "echo LAUF=$?"):
        m.tippe(zeile)
        m.taste("ret")
        time.sleep(4.0)
    b4 = foto_ppm(m, "05-selbsthosting")
    p_lauf = suche(b4, "LAUF=42")
    merke("8.2", "auf dem Stick uebersetzen und ausfuehren",
          "GEHT" if p_lauf and p_lauf >= 60 else "GEHT NICHT",
          "'LAUF=42' zu %s %% im Bild" % p_lauf)

    merke("7.5", "keine Abstuerze",
          "GEHT" if lesen.abstuerze(s()) == 0 else "GEHT NICHT",
          "%d Treffer" % lesen.abstuerze(s()))
    return schluss()


def schluss():
    with open(os.path.join(D, "terminal.json"), "w") as f:
        json.dump(ERG, f, indent=1, ensure_ascii=False)
    print("\n-> %s/terminal.json" % D)
    return 0


if __name__ == "__main__":
    sys.exit(main())
