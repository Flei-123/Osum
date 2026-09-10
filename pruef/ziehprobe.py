#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""ziehprobe.py -- WARUM WIRKT DAS ZIEHEN NICHT? Vier Fassungen, eine Messung.

    python3 ziehprobe.py [name] [breite] [hoehe]

STAND DER UNTERSUCHUNG (Runde TUERSCHLOSS, Nachtrag zu 4.1/4.2):

  * Der ZEIGER kommt bildpunktgenau an: `zeigerprobe.py` misst fuenf
    Orte mit dx=0 dy=0. Die Koordinaten sind also nicht das Problem.
  * Ein KLICK wirkt: im Durchgang dk1280 stehen `kl=44` und 36
    `taskbar: click`-Zeilen, das Startmenue geht auf.
  * Beim ZIEHEN steht `kl=0` -- der Kern hat die Taste nie unten
    gesehen. Und zwar auf dem ALTEN Abbild (merge8) genauso wie auf dem
    neuen; eine Regression dieser Runde ist es nicht.

Der Unterschied zwischen beiden Faellen liegt in `klick.py`: `klick()`
schickt `mouse_button 1` und gleich darauf `mouse_button 0`, `ziehe()`
schickt dazwischen `mouse_move`. Diese Probe trennt die moeglichen
Ursachen, indem sie VIER Fassungen desselben Zuges faehrt und nach jeder
den Klickzaehler des Kerns liest (`kl=` im Puls):

  A  druecken, warten, loslassen -- OHNE Bewegung dazwischen
  B  druecken, EIN grosser Schritt, loslassen
  C  druecken, viele kleine Schritte, loslassen (die heutige Fassung)
  D  druecken, Bewegung, und die Taste bei JEDEM Schritt neu senden

Wenn A zaehlt und C nicht, verliert die Bewegung die Taste. Wenn schon A
nicht zaehlt, kommt der Druck an dieser Stelle des Schirms gar nicht an.
"""
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
from klick import Maschine

NAME = sys.argv[1] if len(sys.argv) > 1 else "zieh"
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


def klicks():
    v = re.findall(r"kl=(\d+)", s())
    return int(v[-1]) if v else -1


def fenster():
    aus = {}
    for m in re.finditer(r"wm: fen i=\d+ id=(\d+) x=(\d+) y=(\d+) w=(\d+) "
                         r"h=(\d+) lay=(\d+) fl=(\d+)", s()):
        aus[int(m.group(1))] = tuple(int(m.group(k)) for k in range(2, 8))
    return aus


def warte_puls(vorher, frist=45):
    """Auf eine NEUE Pulszeile warten -- der Zaehler steht nur dort."""
    bis = time.time() + frist
    while time.time() < bis:
        if len(re.findall(r"kl=(\d+)", s())) > vorher:
            return True
        time.sleep(0.4)
    return False


def main():
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(BREITE), str(HOEHE)], check=True,
                   capture_output=True, text=True, timeout=60)
    t0 = time.time()
    while time.time() - t0 < 180:
        if "taskbar: start x=" in s():
            break
        time.sleep(0.3)
    print("hochgefahren nach %.1f s" % (time.time() - t0), flush=True)
    # Auf die Fensterliste warten -- sie haengt am Puls.
    bis = time.time() + 120
    while time.time() < bis and not fenster():
        time.sleep(0.5)
    m = Maschine(os.path.join(D, "mon.sock"), BREITE, HOEHE)

    f = fenster()
    ziel = None
    for wid, (x, y, w, h, lay, fl) in f.items():
        if lay == 1 and (fl & 3) == 0 and w >= 200:
            ziel = (wid, x, y, w, h)
    if not ziel:
        print("kein Fenster mit Schmuck:", f)
        return 1
    wid, x, y, w, h = ziel
    print("Zielfenster id=%d x=%d y=%d w=%d h=%d" % (wid, x, y, w, h),
          flush=True)
    tx, ty = x + 2 + 40, y + 11          # Titelleiste, linke Haelfte

    def runde(nr, tue):
        n = len(re.findall(r"kl=(\d+)", s()))
        vor_k = klicks()
        vor_f = fenster().get(wid)
        tue()
        warte_puls(n, 45)
        nach_k = klicks()
        nach_f = fenster().get(wid)
        print("  %s  kl %d -> %d   Fenster %s -> %s"
              % (nr, vor_k, nach_k, vor_f, nach_f), flush=True)
        return nach_k > vor_k

    print("\nA: druecken, warten, loslassen (keine Bewegung)", flush=True)
    def a():
        m.gehe(tx, ty)
        m.sag("mouse_button 1", 0.3)
        time.sleep(0.5)
        m.sag("mouse_button 0", 0.3)
    runde("A", a)

    print("\nB: druecken, EIN Schritt, loslassen", flush=True)
    def b():
        m.gehe(tx, ty)
        m.sag("mouse_button 1", 0.3)
        m.sag("mouse_move 120 90", 0.3)
        m.sag("mouse_button 0", 0.3)
    runde("B", b)

    print("\nC: die heutige Fassung (viele kleine Schritte)", flush=True)
    def c():
        m.ziehe(tx, ty, tx + 150, ty + 110)
    runde("C", c)

    print("\nD: Taste bei JEDEM Schritt neu senden", flush=True)
    def d():
        m.gehe(tx, ty)
        m.sag("mouse_button 1", 0.2)
        for _ in range(6):
            m.sag("mouse_move 25 18", 0.08)
            m.sag("mouse_button 1", 0.05)
        m.sag("mouse_button 0", 0.2)
    runde("D", d)

    print("\nZum Vergleich: ein gewoehnlicher Klick auf den Startknopf",
          flush=True)
    def e():
        m.klick_auf(18, HOEHE - 20)
    runde("E", e)

    m.sag("quit", 0.2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
