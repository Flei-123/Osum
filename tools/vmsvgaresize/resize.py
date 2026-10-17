# SPDX-License-Identifier: GPL-2.0-only
# tools/vmsvgaresize/resize.py -- desktop after host resolution changes (r1004), called by tools/vmsvgaresize/run.sh.
# usage: resize.py <monitor sock> <vnc sock> <base> <serial file> <settle seconds> <WxH,WxH,...>
# Boots nothing itself. Logs in, waits for the desktop, then asks QEMU for each size through the VNC SetDesktopSize message (the same
# kernel path as a VirtualBox hint: vmsvga.host_pending -> vmode.follow_host). After every size the screendump is saved
# (<base>.<n>.ppm) and measured; one line per size is written to <base>.res:
#   <n> <w> <h> <black share of the upper 60 % of the screen> <taskbar rows: distinct-colour rows in the bottom 60 rows> <share of black pixels in the bottom row> <expected w> <expected h> <bar duplicate share> <start menu centre x or -1> <start menu bottom row or -1>
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
    lastblack = float(np.mean(np.all(img[h - 1] < 6, axis=1)))
    # r1006: the bar must be painted with the NEW row length. A stale stride shows the left part of the bar again, shifted by the old
    # width. Measure it: the share of bar pixels (not the white bar colour) that equal the pixel `d` columns to the left, best `d`.
    bar = img[h - 46 : h - 6].astype(np.int16)
    ink = bar.min(axis=2) < 200
    dup = 0.0
    for d in range(300, w - 100, 4):
        n = int(ink[:, d:].sum())
        if n < 200:
            continue
        eq = np.all(bar[:, d:] == bar[:, :-d], axis=2) & ink[:, d:]
        dup = max(dup, float(eq.sum()) / n)
    return w, h, black, rows, lastblack, dup


def menu_find(mon, tag):
    f = mon.dump("%s.m.ppm" % (base + "." + tag))
    w, h, b = ppm_rgb(f)
    img = np.frombuffer(b, dtype=np.uint8).reshape(h, w, 3).astype(np.int16)
    m = np.all(np.abs(img[: h - 40] - np.array([248, 249, 251])) <= 3, axis=2)
    rows = np.where(m.sum(axis=1) >= 300)[0]
    if len(rows) < 100:
        return -1, -1
    cols = np.where(m[rows[0] : rows[-1] + 1].sum(axis=0) >= 100)[0]
    return int((cols[0] + cols[-1]) // 2), int(rows[-1])


def menu_probe(mon, tag):
    # r1007: open the start menu (Super key) and measure where its panel stands: horizontal centre and bottom edge. The panel colour
    # is (248,249,251); the menu must be centred on the CURRENT screen and end above the bar. The key toggles: if the first press
    # finds no menu (it was open and is closed now), press once more. Esc closes it at the end.
    res = (-1, -1)
    for _ in range(2):
        mon.cmd("sendkey meta_l", 3.0)
        res = menu_find(mon, tag)
        if res[0] >= 0:
            break
    mon.cmd("sendkey esc", 1.5)
    return res


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
    import re
    # the kernel plays the hints from its own clock (serial `vmsvga: testhint WxH rc=N`), also before the login: every step waits
    # for the NEXT line, lets the desktop settle and expects exactly the size of the newest line
    last = read_serial().count("vmsvga: testhint ")
    steps = len(sizes.split(","))
    for n in range(1, steps + 1):
        wait_for(lambda t: t.count("vmsvga: testhint ") > last, 60)
        time.sleep(settle)
        t = read_serial()
        last = t.count("vmsvga: testhint ")
        m = re.findall(r"vmsvga: testhint (\d+)x(\d+) rc=(\d+)", t)
        ew, eh = (int(m[-1][0]), int(m[-1][1])) if m else (0, 0)
        r = measure(mon, str(n))
        mcx, mbot = menu_probe(mon, str(n))
        out.write("%d %d %d %.3f %d %.3f %d %d %.3f %d %d\n" % (n, r[0], r[1], r[2], r[3], r[4], ew, eh, r[5], mcx, mbot))
        out.flush()
    out.close()
    mon.quit()


main()
