# SPDX-License-Identifier: GPL-2.0-only
# tools/vmsvgaboot/boot.py -- called by tools/vmsvgaboot/run.sh: log in, take one screendump, measure it.
# usage: boot.py <monitor sock> <vnc sock> <base> <serial file>
# writes <base>.login (1/0), <base>.res ("<w> <h> <black share of the upper 60 %> <taskbar rows>"), <base>.bar (height in px of the bottom bar,
# measured as the number of bottom rows whose colour differs from the wallpaper row 200 px above... see bar_height)
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "vmsvga"))
from vnclib import Mon, ppm_rgb  # noqa: E402

mon_sock, vnc_sock, base, serial = sys.argv[1:5]


def read_serial():
    try:
        return open(serial, errors="replace").read()
    except OSError:
        return ""


def wait_for(pred, timeout):
    end = time.time() + timeout
    while time.time() < end:
        if pred(read_serial()):
            return True
        time.sleep(0.3)
    return False


def main():
    mon = Mon(mon_sock)
    if not wait_for(lambda t: "glogin: bereit" in t, 240):
        open(base + ".login", "w").write("0")
        mon.quit()
        return
    time.sleep(6)
    for c in "startkennwort":
        mon.cmd("sendkey " + c, 0.12)
    mon.cmd("sendkey ret", 0.3)
    ok = wait_for(lambda t: "glogin: angemeldet als" in t, 60)
    open(base + ".login", "w").write("1" if ok else "0")
    if not ok:
        mon.quit()
        return
    time.sleep(15)
    f = mon.dump(base + ".d.ppm")
    w, h, b = ppm_rgb(f)
    img = np.frombuffer(b, dtype=np.uint8).reshape(h, w, 3)
    up = img[: int(h * 0.6)]
    black = float(np.mean(np.all(up < 6, axis=2)))
    bot = img[h - 60:]
    ref = img[max(0, h - 330): h - 270].reshape(-1, 3).mean(axis=0)
    rows = int(np.sum(np.abs(bot.astype(int).mean(axis=1) - ref).max(axis=1) > 12))
    # bar height: scan upwards from the last row while the row differs from the wallpaper row 300 px above (the bar is a solid band)
    refrow = img[max(0, h - 300)].astype(int)
    hb = 0
    for y in range(h - 1, h - 200, -1):
        row = img[y].astype(int)
        if np.mean(np.abs(row - refrow).max(axis=1) > 12) > 0.5:
            hb += 1
        else:
            break
    open(base + ".res", "w").write("%d %d %.3f %d\n" % (w, h, black, rows))
    open(base + ".bar", "w").write("%d\n" % hb)
    mon.quit()


main()
