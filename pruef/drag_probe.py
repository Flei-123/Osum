#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    drag_probe.py -- WARUM WIRKT DAS ZIEHEN NICHT? Four Fassungen, eine Measure.
    python3 drag_probe.py [name] [width] [height]
"""
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
from click_driver import Maschine

NAME = sys.argv[1] if len(sys.argv) > 1 else "zieh"
WIDTH = int(sys.argv[2]) if len(sys.argv) > 2 else 1280
HEIGHT = int(sys.argv[3]) if len(sys.argv) > 3 else 800
D = os.path.join(HIER, "runs", NAME)
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


def window():
    aus = {}
    for m in re.finditer(r"wm: fen i=\d+ id=(\d+) x=(\d+) y=(\d+) w=(\d+) "
                         r"h=(\d+) lay=(\d+) fl=(\d+)", s()):
        aus[int(m.group(1))] = tuple(int(m.group(k)) for k in range(2, 8))
    return aus


def wait_pulse(vorher, deadline=45):
    """Auf eine NEUE Pulszeile warten -- der Zaehler steht nur dort."""
    bis = time.time() + deadline
    while time.time() < bis:
        if len(re.findall(r"kl=(\d+)", s())) > vorher:
            return True
        time.sleep(0.4)
    return False


def main():
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(WIDTH), str(HEIGHT)], check=True,
                   capture_output=True, text=True, timeout=60)
    t0 = time.time()
    while time.time() - t0 < 180:
        if "taskbar: start x=" in s():
            break
        time.sleep(0.3)
    print("hochgefahren nach %.1f s" % (time.time() - t0), flush=True)
    # Auf die Fensterliste warten -- sie haengt am Puls.
    bis = time.time() + 120
    while time.time() < bis and not window():
        time.sleep(0.5)
    m = Maschine(os.path.join(D, "mon.sock"), WIDTH, HEIGHT)

    f = window()
    target = None
    for wid, (x, y, w, h, lay, fl) in f.items():
        if lay == 1 and (fl & 3) == 0 and w >= 200:
            target = (wid, x, y, w, h)
    if not target:
        print("kein Fenster mit Schmuck:", f)
        return 1
    wid, x, y, w, h = target
    print("Zielfenster id=%d x=%d y=%d w=%d h=%d" % (wid, x, y, w, h),
          flush=True)
    tx, ty = x + 2 + 40, y + 11          # Titelleiste, linke Haelfte

    def runde(nr, act):
        n = len(re.findall(r"kl=(\d+)", s()))
        vor_k = klicks()
        vor_f = window().get(wid)
        act()
        wait_pulse(n, 45)
        nach_k = klicks()
        nach_f = window().get(wid)
        print("  %s  kl %d -> %d   Fenster %s -> %s"
              % (nr, vor_k, nach_k, vor_f, nach_f), flush=True)
        return nach_k > vor_k

    print("\nA: druecken, warten, loslassen (keine Bewegung)", flush=True)
    def a():
        m.go_to(tx, ty)
        m.say("mouse_button 1", 0.3)
        time.sleep(0.5)
        m.say("mouse_button 0", 0.3)
    runde("A", a)

    print("\nB: druecken, EIN Schritt, loslassen", flush=True)
    def b():
        m.go_to(tx, ty)
        m.say("mouse_button 1", 0.3)
        m.say("mouse_move 120 90", 0.3)
        m.say("mouse_button 0", 0.3)
    runde("B", b)

    print("\nC: die heutige Fassung (viele kleine Schritte)", flush=True)
    def c():
        m.ziehe(tx, ty, tx + 150, ty + 110)
    runde("C", c)

    print("\nD: Taste bei JEDEM Schritt neu senden", flush=True)
    def d():
        m.go_to(tx, ty)
        m.say("mouse_button 1", 0.2)
        for _ in range(6):
            m.say("mouse_move 25 18", 0.08)
            m.say("mouse_button 1", 0.05)
        m.say("mouse_button 0", 0.2)
    runde("D", d)

    print("\nZum Vergleich: ein gewoehnlicher Klick auf den Startknopf",
          flush=True)
    def e():
        m.klick_auf(18, HEIGHT - 20)
    runde("E", e)

    m.say("quit", 0.2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
