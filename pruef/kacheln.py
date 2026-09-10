#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""kacheln.py -- JEDE KACHEL DES KONTROLLZENTRUMS, EINZELN.

    python3 kacheln.py <name> <breite> <hoehe> <uiscale>

Justin: "beim Klicken passiert irgendwas ganz Komisches, danach geht
gar nichts mehr". Das ist der Satz, der nachgestellt werden muss --
und zwar so, dass hinterher feststeht, WELCHE Kachel es war.

Geklickt wird NICHT auf geratene Stellen. Das Kontrollzentrum meldet
seine Lage selbst (`qs: geo x= y= w= h=`), und die Kachelmasse stehen
in kernel/user/qs.fi:
    PAD=6*s  GAP=8*s  TW=176*s  TH=PAD/2+IC+4s+ZH+3s+ZH+PAD/2
Zwei Spalten, drei Reihen. Nach JEDEM Klick wird gefragt:
  * kam ein panic?
  * lebt das Kontrollzentrum noch (malt es weiter)?
  * reagiert die Leiste noch (Uhr laeuft)?
Das dritte ist Justins "danach geht gar nichts mehr" in messbar.
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

NAME = sys.argv[1] if len(sys.argv) > 1 else "kach"
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
    print("%-8s %-40s %-12s %s" % (nr, was[:40], erg, str(beleg)[:60]),
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


def uhr(s):
    """Die letzte Uhrzeit, die die Leiste gemalt hat."""
    t = re.findall(r"t=(\d\d:\d\d:\d\d)", s)
    return t[-1] if t else None


def main():
    extra = ("uiscale=%d " % SCALE if SCALE != 1 else "") + "shape=osum"
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(BREITE), str(HOEHE), extra],
                   check=True, cwd=HIER,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    m = Maschine(os.path.join(D, "mon.sock"), BREITE, HOEHE)
    m.verbinde()
    merke("0.1", "Leiste steht", "ja" if warte_auf("taskbar: state") else "NEIN")
    time.sleep(4)

    # Kontrollzentrum oeffnen. NICHT geraten: die Leiste meldet die
    # Lage ihrer Tray-Felder selbst (`taskbar: field clock x= y= w= h=`),
    # und y ist dabei LEISTENINTERN -- der Schirmwert ist Leistenoberkante
    # plus y. Ein Klick auf gut Glueck landete im ersten Anlauf auf dem
    # Schreibtisch: `taskbar: ... clicks=1` blieb stehen, `qs: open` kam
    # nie, und die sechs Kachelklicks danach haben NICHTS gemessen.
    s = serial()
    # DAS NETZFELD und nicht die Uhr: `taskbar.fi` oeffnet das Panel
    # ueber F_NET (und ueber den Lautsprecher), die Uhr daneben ist nur
    # Anzeige. Ein Klick auf die Uhr erhoeht `clicks`, tut aber sonst
    # nichts -- gemessen: `qs: open` blieb bei 0.
    f = re.findall(r"taskbar: field net x=(\d+) y=(\d+) w=(\d+) h=(\d+)", s)
    if f:
        fx, fy, fw, fh = (int(v) for v in f[-1])
        bar_top = HOEHE - 80 if SCALE == 2 else HOEHE - 40
        cx, cy = fx + fw // 2, bar_top + fy + fh // 2
    else:
        cx, cy = BREITE - 150, HOEHE - 40
    merke("0.15", "Klick auf Netzfeld (oeffnet qs)", "bei %d,%d" % (cx, cy))
    m.klick_auf(cx, cy)
    time.sleep(3)
    s = serial()
    geo = re.findall(r"qs: geo x=(\d+) y=(\d+) w=(\d+) h=(\d+)", s)
    if not geo:
        merke("0.2", "Kontrollzentrum offen", "NEIN", "keine qs:geo-Zeile")
        with open(os.path.join(D, "befund.json"), "w") as f:
            json.dump(BEFUND, f, indent=1, ensure_ascii=False)
        return
    x, y, w, h = (int(v) for v in geo[-1])
    merke("0.2", "Kontrollzentrum offen", "ja", "x=%d y=%d %dx%d" % (x, y, w, h))
    m.foto(os.path.join(SHOTS, "00-offen.png"))

    # Kachelraster nachrechnen, genau wie qs.fi es tut.
    s_ = SCALE
    PAD, GAP, TW = 6 * s_, 8 * s_, 176 * s_
    IC = 24 * s_
    ZH = 15 * s_ + 4          # text_h ~ px_ui + Luft
    TH = PAD // 2 + IC + 4 * s_ + ZH + 3 * s_ + ZH + PAD // 2

    lebt_vorher = True
    for t in range(6):
        sp, re_ = t % 2, t // 2
        tx = x + PAD + sp * (TW + GAP) + TW // 2
        ty = y + PAD + re_ * (TH + GAP) + TH // 2
        vor = len(serial())
        u1 = uhr(serial())
        m.klick_auf(tx, ty)
        time.sleep(2.5)
        neu = serial()[vor:]
        p = [z.strip() for z in neu.splitlines() if "panic:" in z]
        u2 = uhr(serial())
        lebt = (u2 is not None and u2 != u1)
        merke("K%d" % t, "Kachel %d bei (%d,%d)" % (t, tx, ty),
              "PANIC" if p else ("ok" if lebt else "STILL"),
              p[:2] if p else "Uhr %s -> %s" % (u1, u2))
        m.foto(os.path.join(SHOTS, "k%d.png" % t))
        if p or not lebt:
            lebt_vorher = False
            break

    s = serial()
    alle = [z.strip() for z in s.splitlines() if "panic:" in z]
    merke("9.1", "panics gesamt", "KEINE" if not alle else "JA", alle[:4])
    merke("9.2", "System lebt am Ende", "ja" if lebt_vorher else "NEIN")
    with open(os.path.join(D, "befund.json"), "w") as f:
        json.dump(BEFUND, f, indent=1, ensure_ascii=False)
    try:
        m.sag("quit")
    except Exception:
        pass


if __name__ == "__main__":
    main()
