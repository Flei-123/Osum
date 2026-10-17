# SPDX-License-Identifier: GPL-2.0-only
# tools/vmsvgaresize/resize.py -- desktop after host resolution changes (r1004), called by tools/vmsvgaresize/run.sh.
# usage: resize.py <monitor sock> <vnc sock> <base> <serial file> <settle seconds> <WxH,WxH,...>
# Boots nothing itself. Logs in, waits for the desktop, then asks QEMU for each size through the VNC SetDesktopSize message (the same
# kernel path as a VirtualBox hint: vmsvga.host_pending -> vmode.follow_host). After every size the screendump is saved
# (<base>.<n>.ppm) and measured; one line per size is written to <base>.res:
#   <n> <w> <h> <black share of the upper 60 % of the screen> <taskbar rows: distinct-colour rows in the bottom 60 rows> <bottom row all black 1/0>
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "vmsvga"))
from vnclib import Mon, ppm_rgb  # noqa: E402
import subprocess  # noqa: E402

mon_sock, vnc_sock, base, serial, settle, sizes = sys.argv[1:7]
settle = float(settle)


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


def measure(mon, tag):
    f = mon.dump("%s.%s.ppm" % (base, tag))
    w, h, b = ppm_rgb(f)
    img = np.frombuffer(b, dtype=np.uint8).reshape(h, w, 3)
    up = img[: int(h * 0.6)]
    black = float(np.mean(np.all(up < 6, axis=2)))
    # the bar: bottom 60 rows must not look like the plain wallpaper -> count rows whose colour differs from the row 70 rows up
    bot = img[h - 60 :]
    ref = img[max(0, h - 130) : h - 70].reshape(-1, 3).mean(axis=0) if h > 200 else np.zeros(3)
    rows = int(np.sum(np.abs(bot.astype(int).mean(axis=1) - ref).max(axis=1) > 12))
    lastblack = int(np.all(img[h - 1] < 6))
    return w, h, black, rows, lastblack


def main():
    mon = Mon(mon_sock)
    if not wait_for(lambda t: "glogin: bereit" in t, 200):
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
    time.sleep(settle)
    out = open(base + ".res", "w")
    n = 1
    for sz in sizes.split(","):
        w, h = [int(x) for x in sz.split("x")]
        # the kernel word `vmsvgahints` plays the hint itself (serial: `vmsvga: testhint WxH rc=N`); wait for that line
        wait_for(lambda t: t.count("vmsvga: testhint ") >= n, 60)
        # the poll is rate limited to 1 s and wants two equal polls in a row; then the desktop needs a moment to redraw
        time.sleep(settle)
        r = measure(mon, str(n))
        out.write("%d %d %d %.3f %d %d\n" % ((n, r[0], r[1], r[2], r[3], r[4])))
        out.flush()
        n += 1
    out.close()
    mon.quit()


main()
