# SPDX-License-Identifier: GPL-2.0-only
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
    bot = img[h - 60 :]
    ref = img[max(0, h - 130) : h - 70].reshape(-1, 3).mean(axis=0) if h > 200 else np.zeros(3)
    rows = int(np.sum(np.abs(bot.astype(int).mean(axis=1) - ref).max(axis=1) > 12))
    lastblack = float(np.mean(np.all(img[h - 1] < 6, axis=1)))
    bar = img[h - 46 : h - 6].astype(np.int16)
    ink = bar.min(axis=2) < 200
    dup = 0.0
    for d in range(300, w - 100, 4):
        n = int(ink[:, d:].sum())
        if n < 200:
            continue
        eq = np.all(bar[:, d:] == bar[:, :-d], axis=2) & ink[:, d:]
        dup = max(dup, float(eq.sum()) / n)
    band = np.concatenate([up[:, :24].reshape(-1, 3), up[:, w - 24 :].reshape(-1, 3), up[:8].reshape(-1, 3)])
    wedge = float(np.mean(np.all(band >= 235, axis=1)))
    return w, h, black, rows, lastblack, dup, wedge


def menu_find(mon, tag):
    f = mon.dump("%s.m.ppm" % (base + "." + tag))
    w, h, b = ppm_rgb(f)
    img = np.frombuffer(b, dtype=np.uint8).reshape(h, w, 3).astype(np.int16)
    m = np.all(np.abs(img[: h - 40] - np.array([248, 249, 251])) <= 3, axis=2)
    rows = np.where(m.sum(axis=1) >= 300)[0]
    if len(rows) < 100:
        return -1, -1, w, h
    cols = np.where(m[rows[0] : rows[-1] + 1].sum(axis=0) >= 100)[0]
    return int((cols[0] + cols[-1]) // 2), int(rows[-1]), w, h


def menu_probe(mon, tag, leave_open):
    res = (-1, -1, 0, 0)
    carry = menu_find(mon, tag + "c")
    if carry[0] >= 0:
        mon.cmd("sendkey meta_l", 2.0)
        if menu_find(mon, tag)[0] >= 0:
            mon.cmd("sendkey meta_l", 2.0)
    for _ in range(2):
        mon.cmd("sendkey meta_l", 3.0)
        res = menu_find(mon, tag)
        if res[0] >= 0:
            break
    if not leave_open:
        mon.cmd("sendkey meta_l", 2.0)
    return carry + res


def main():
    mon = Mon(mon_sock)
    if not wait_for(lambda t: "glogin: ready" in t or t.count("glogin: rect id=") >= 3, 200):
        open(base + ".login", "w").write("0")
        mon.quit()
        return
    time.sleep(6)
    for c in "startkennwort":
        mon.cmd("sendkey " + c, 0.12)
    mon.cmd("sendkey ret", 0.3)
    ok = wait_for(lambda t: "glogin: angemeldet als" in t or "glogin: autostart" in t or "glogin: uid=" in t, 60)
    open(base + ".login", "w").write("1" if ok else "0")
    if not ok:
        mon.quit()
        return
    time.sleep(settle)
    out = open(base + ".res", "w")
    early = open(base + ".early", "w")
    import re
    last = read_serial().count("vmsvga: testhint ")
    steps = len(sizes.split(","))
    for n in range(1, steps + 1):
        wait_for(lambda t: t.count("vmsvga: testhint ") > last, 60)
        time.sleep(2.0)
        re_ = measure(mon, "%de" % n)
        early.write("%d %d\n" % (n, re_[3]))
        early.flush()
        time.sleep(max(0.0, settle - 2.0))
        t = read_serial()
        last = t.count("vmsvga: testhint ")
        m = re.findall(r"vmsvga: testhint (\d+)x(\d+) rc=(\d+)(?: now=(\d+)x(\d+))?", t)
        ew, eh = (int(m[-1][0]), int(m[-1][1])) if m else (0, 0)
        if m and os.environ.get("RESIZE_USE_NOW") == "1" and m[-1][3]:
            ew, eh = int(m[-1][3]), int(m[-1][4])
        r = measure(mon, str(n))
        ccx, cbot, cw, ch, mcx, mbot, mw, mh = menu_probe(mon, str(n), n < steps)
        out.write("%d %d %d %.3f %d %.3f %d %d %.3f %d %d %d %d %d %d %d %d %.3f\n" % (n, r[0], r[1], r[2], r[3], r[4], ew, eh, r[5], mcx, mbot, mw, mh, ccx, cbot, cw, ch, r[6]))
        out.flush()
    out.close()
    early.close()
    mon.quit()


main()
