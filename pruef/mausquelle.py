#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""mausquelle.py -- WELCHES ZEIGEGERAET BEDIENT DER MONITOR?

    python3 mausquelle.py [name] [breite] [hoehe]

DER FUND, UM DEN ES GEHT. `qemu ... -device usb-tablet` haengt ZWEI
Zeigegeraete an die Maschine, und `info mice` sagt, welches der Monitor
gerade bedient:

      Mouse #2: QEMU PS/2 Mouse
    * Mouse #3: QEMU HID Tablet (absolute)

Der Stern steht auf dem TABLET, und ein Tablet ist ABSOLUT. `klick.py`
rechnet dagegen RELATIV: es faehrt mit `mouse_move -200 -200` in die
linke obere Ecke, nimmt an, der Anschlag halte dort, und rechnet von
(0,0) aus weiter. Fuer ein absolutes Geraet ist `mouse_move dx dy` aber
kein Schritt, sondern ein ORT -- die ganze Rechnerei geht ins Leere,
sobald mehr als ein Sprung noetig ist.

Gemessen wurde dabei genau das Verhalten, das dazu passt:
  * ein EINZELNER Klick auf den Startknopf wirkt (dk1280: kl=44),
  * ein Zug auf der Titelleiste zaehlt NICHT EINE Taste (kl 0 -> 0),
  * und nach dem Zug steht der Zeiger auf `xy=18,400` statt `xy=18,780`.

Diese Probe schaltet mit `mouse_set 2` auf die PS/2-Maus um -- das
relative Geraet, fuer das `klick.py` gebaut ist -- und misst danach
denselben Zug noch einmal.
"""
import os
import re
import socket
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
from klick import Maschine

NAME = sys.argv[1] if len(sys.argv) > 1 else "mq"
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


def warte_puls(n, frist=45):
    bis = time.time() + frist
    while time.time() < bis:
        if len(re.findall(r"kl=(\d+)", s())) > n:
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
    bis = time.time() + 120
    while time.time() < bis and not fenster():
        time.sleep(0.5)

    m = Maschine(os.path.join(D, "mon.sock"), BREITE, HOEHE)

    # 1. Wer ist es?
    m.s.sendall(b"info mice\n")
    time.sleep(1.0)
    try:
        roh = m.s.recv(65536).decode("utf-8", "replace")
    except OSError:
        roh = ""
    zeilen = [z.strip() for z in roh.splitlines() if "Mouse #" in z]
    print("\ninfo mice VORHER:")
    for z in zeilen:
        print("   ", z)

    f = fenster()
    ziel = None
    for wid, (x, y, w, h, lay, fl) in f.items():
        if lay == 1 and (fl & 3) == 0 and w >= 200:
            ziel = (wid, x, y, w, h)
    if not ziel:
        print("kein Fenster mit Schmuck:", f)
        return 1
    wid, x, y, w, h = ziel
    tx, ty = x + 2 + 40, y + 11
    print("\nZielfenster id=%d x=%d y=%d w=%d h=%d, Titelleiste (%d,%d)"
          % (wid, x, y, w, h, tx, ty), flush=True)

    def zug(titel):
        n = len(re.findall(r"kl=(\d+)", s()))
        vk, vf = klicks(), fenster().get(wid)
        m.ziehe(tx, ty, tx + 180, ty + 130)
        warte_puls(n, 45)
        nk, nf = klicks(), fenster().get(wid)
        bewegt = bool(vf and nf and (abs(nf[0] - vf[0]) > 20
                                     or abs(nf[1] - vf[1]) > 20))
        print("  %-22s kl %d -> %d   %s -> %s   VERSCHOBEN: %s"
              % (titel, vk, nk, vf, nf, "JA" if bewegt else "NEIN"),
              flush=True)
        return bewegt

    print("\nZug mit dem Geraet, das QEMU von sich aus bedient:", flush=True)
    a = zug("tablet (absolut)")

    # 2. Auf die PS/2-Maus umschalten und noch einmal.
    m.s.sendall(b"mouse_set 2\n")
    time.sleep(1.0)
    try:
        m.s.recv(65536)
    except OSError:
        pass
    m.s.sendall(b"info mice\n")
    time.sleep(1.0)
    try:
        roh2 = m.s.recv(65536).decode("utf-8", "replace")
    except OSError:
        roh2 = ""
    print("\ninfo mice NACH 'mouse_set 2':")
    for z in [q.strip() for q in roh2.splitlines() if "Mouse #" in q]:
        print("   ", z)

    print("\nDerselbe Zug, jetzt ueber die PS/2-Maus:", flush=True)
    b = zug("ps2 (relativ)")

    m.sag("quit", 0.2)
    print("\nERGEBNIS: tablet=%s  ps2=%s"
          % ("JA" if a else "NEIN", "JA" if b else "NEIN"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
