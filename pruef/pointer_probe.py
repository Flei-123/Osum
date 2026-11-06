#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    pointer_probe.py -- KOMMT DER CURSOR DA AN, WO ER HIN SOLL?
    python3 pointer_probe.py [name] [width] [height]
"""
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
from click_driver import Maschine

NAME = sys.argv[1] if len(sys.argv) > 1 else "zp"
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


def xy_count():
    v = re.findall(r"xy=(\d+),(\d+)", s())
    return (int(v[-1][0]), int(v[-1][1])) if v else None


def wait_new_xy(alt, deadline=40):
    bis = time.time() + deadline
    while time.time() < bis:
        v = re.findall(r"xy=(\d+),(\d+)", s())
        if v and len(v) > alt:
            return (int(v[-1][0]), int(v[-1][1])), len(v)
        time.sleep(0.4)
    v = re.findall(r"xy=(\d+),(\d+)", s())
    return ((int(v[-1][0]), int(v[-1][1])) if v else None), len(v)


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
    time.sleep(4)
    m = Maschine(os.path.join(D, "mon.sock"), WIDTH, HEIGHT)

    n = len(re.findall(r"xy=(\d+),(\d+)", s()))
    print("Zeigerlage beim Start: %s" % (xy_count(),), flush=True)

    ziele = [(66, 51), (580, 436), (18, HEIGHT - 20), (300, 200), (640, 400)]
    print("\n%-14s %-14s %s" % ("gewollt", "gemessen", "Abweichung"))
    for (zx, zy) in ziele:
        m.go_to(zx, zy)
        time.sleep(1.0)
        ist, n = wait_new_xy(n, 40)
        if ist:
            print("%-14s %-14s dx=%+d dy=%+d"
                  % ("(%d,%d)" % (zx, zy), "(%d,%d)" % ist,
                     ist[0] - zx, ist[1] - zy), flush=True)
        else:
            print("%-14s %-14s -" % ("(%d,%d)" % (zx, zy), "keine Meldung"),
                  flush=True)

    m.say("quit", 0.2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
