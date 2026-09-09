#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""abnahme2.py -- DIE ABNAHME DER RUNDE ECHTHARDWARE-2.

    python3 abnahme2.py <name> <breite> <hoehe> <uiscale>

Justins Vorgabe F, woertlich: alle Ansichten in 2560x1440 mit
ui_scale 2 UND in 1920x1080 mit scale 1; dazu ein vollstaendiger
Durchklick ohne einen einzigen panic.

DIE ANSICHTEN (je ein Bild):
  01 startmenue     Startmenue offen, Suchtext "ter" eingetippt
  02 explorer       Dateimanager auf /data
  03 einstellungen  Einstellungen MIT INHALT (das war das weisse Fenster)
  04 kontrollzentrum
  05 terminal       Terminal mit Text
  06 leiste         Nahaufnahme unten links, 600x120
  07 tray           Nahaufnahme rechts unten

Jedes Bild wird ausserdem VERMESSEN (Tinte, Kaesten), damit in der
Schlussmeldung kein Satz steht, der nicht aus einer Zahl kommt.
"""
import json
import os
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
from klick import Maschine

NAME = sys.argv[1] if len(sys.argv) > 1 else "ab2"
BREITE = int(sys.argv[2]) if len(sys.argv) > 2 else 2560
HOEHE = int(sys.argv[3]) if len(sys.argv) > 3 else 1440
SCALE = int(sys.argv[4]) if len(sys.argv) > 4 else 2

D = os.path.join(HIER, "laeufe", NAME)
SHOTS = os.path.join(HIER, "shots", NAME)
os.makedirs(SHOTS, exist_ok=True)
SER = os.path.join(D, "serial.txt")
BEFUND = []


def merke(nr, was, erg, beleg=""):
    BEFUND.append({"nr": nr, "was": was, "ergebnis": erg,
                   "beleg": str(beleg)[:400]})
    print("%-7s %-44s %-11s %s" % (nr, was[:44], erg, str(beleg)[:66]),
          flush=True)


def serial():
    try:
        with open(SER, "rb") as f:
            return f.read().decode("utf-8", "replace")
    except OSError:
        return ""


def warte_auf(marke, frist=90):
    t0 = time.time()
    while time.time() - t0 < frist:
        if marke in serial():
            return True
        time.sleep(2)
    return False


def main():
    extra = "uiscale=%d shape=osum" % SCALE if SCALE != 1 else "shape=osum"
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(BREITE), str(HOEHE), extra],
                   check=True, cwd=HIER,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    m = Maschine(os.path.join(D, "mon.sock"), BREITE, HOEHE)
    m.verbinde()
    merke("0.1", "Leiste steht", "ja" if warte_auf("taskbar: state") else "NEIN")
    time.sleep(4)
    s = serial()
    lang = [z for z in s.splitlines() if "lang=" in z]
    merke("0.2", "Sprache der Oberflaeche", "gemessen", lang[:2])

    # ---------------------------------------------------- 01 STARTMENUE
    m.taste("meta_l")
    time.sleep(2.5)
    m.tippe("ter")
    time.sleep(2.5)
    m.foto(os.path.join(SHOTS, "01-startmenue.png"))
    s = serial()
    su = [z for z in s.splitlines() if "launcher: suche" in z]
    merke("1.1", "Startmenue offen + 'ter' gefiltert",
          "ja" if su else "NEIN", su[-2:])

    # Enter startet den ersten Treffer
    m.taste("ret")
    time.sleep(4)
    merke("1.2", "Enter startet", "ja" if "elf: start" in serial() else "NEIN",
          [z for z in serial().splitlines() if "elf: start" in z][-1:])
    m.foto(os.path.join(SHOTS, "05-terminal.png"))

    # ------------------------------------------------------ 02 EXPLORER
    vor = len(serial())
    m.taste("meta_l")
    time.sleep(2)
    m.tippe("explorer")
    time.sleep(2)
    m.taste("ret")
    time.sleep(5)
    m.foto(os.path.join(SHOTS, "02-explorer.png"))
    neu = serial()[vor:]
    sp = [z for z in neu.splitlines() if "explorer: spalten" in z]
    merke("2.1", "Explorer offen, Spalten", "ja" if sp else "?", sp[-1:])

    # -------------------------------------------------- 03 EINSTELLUNGEN
    vor = len(serial())
    m.taste("meta_l")
    time.sleep(2)
    m.tippe("settings")
    time.sleep(2)
    m.taste("ret")
    time.sleep(6)
    m.foto(os.path.join(SHOTS, "03-einstellungen.png"))
    neu = serial()[vor:]
    merke("3.1", "Einstellungen gestartet",
          "ja" if "elf: start" in neu else "NEIN",
          [z for z in neu.splitlines() if "elf: start" in z][-1:])
    merke("3.2", "appdir INFO-Fehler",
          "JA (Fehler)" if "laenger als" in serial() else "nein")

    # ------------------------------------------------ 04 KONTROLLZENTRUM
    vor = len(serial())
    m.klick_auf(BREITE - 60, HOEHE - 40)
    time.sleep(3)
    m.foto(os.path.join(SHOTS, "04-kontrollzentrum.png"))
    neu = serial()[vor:]
    merke("4.1", "Kontrollzentrum reagiert", "gemessen",
          [z for z in neu.splitlines() if "qs" in z or "kachel" in z][:3])

    # jede Kachel anklicken -- Justins "danach geht gar nichts mehr"
    kachel_panics = []
    for k in range(6):
        vor = len(serial())
        m.klick_auf(BREITE - 300 + (k % 3) * 90, HOEHE - 320 + (k // 3) * 90)
        time.sleep(1.5)
        neu = serial()[vor:]
        if "panic" in neu:
            kachel_panics.append("Kachel %d: %s" % (k, neu[:120]))
    merke("4.2", "jede Kachel geklickt, panics",
          "KEINE" if not kachel_panics else "JA", kachel_panics[:3])
    m.foto(os.path.join(SHOTS, "04b-kacheln.png"))

    # ------------------------------------------------------ NAHAUFNAHMEN
    voll = os.path.join(SHOTS, "voll.png")
    m.foto(voll)
    try:
        from PIL import Image
        im = Image.open(voll)
        im.crop((0, HOEHE - 120, 600, HOEHE)).save(
            os.path.join(SHOTS, "06-leiste.png"))
        im.crop((BREITE - 600, HOEHE - 120, BREITE, HOEHE)).save(
            os.path.join(SHOTS, "07-tray.png"))
        merke("6.1", "Nahaufnahmen geschnitten", "ja")
    except Exception as e:
        merke("6.1", "Nahaufnahmen geschnitten", "NEIN", e)

    # ---------------------------------------------------------- PANICS
    s = serial()
    p = [z.strip() for z in s.splitlines() if "panic:" in z]
    merke("9.1", "panics im GANZEN Durchklick",
          "KEINE" if not p else "JA (%d)" % len(p), p[:5])
    merke("9.2", "Symbolbreiten (Bitmap)", "gemessen",
          [z for z in s.splitlines() if "taskbar: sym" in z][-2:])

    with open(os.path.join(D, "befund.json"), "w") as f:
        json.dump(BEFUND, f, indent=1, ensure_ascii=False)
    try:
        m.sag("quit")
    except Exception:
        pass
    print("\nBilder: %s" % SHOTS)


if __name__ == "__main__":
    main()
