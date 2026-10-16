# SPDX-License-Identifier: GPL-2.0-only
# tools/vmsvga/desktop.py -- REAL DESKTOP check for the VMSVGA driver (called by tools/vmsvga/desktop.sh).
#
# usage: desktop.py <monitor sock> <vnc sock> <base> <serial file> <seed> <rounds> <settle seconds>
# Boots nothing itself. Waits for the sign-in screen, logs in (justin / startkennwort), then plays random mouse + key sequences.
# After every sequence it compares the VNC client's picture (built ONLY from the rectangles the host was told about) with the
# screendump (which reads VRAM directly). A compare only counts when two screendumps in a row are identical (the picture stood
# still); the VNC picture is read between them.
# Output files: <base>.login (1/0), <base>.rounds (one line per compare: "<i> <diff pixels | -1 unstable>"), <base>.updates
import os
import random
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vnclib import Mon, Vnc, ppm_rgb  # noqa: E402

mon_sock, vnc_sock, base, serial, seed, rounds, settle = sys.argv[1:8]
seed = int(seed)
rounds = int(rounds)
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


def compare(mon, vnc, tag):
    """Count pixels where the VNC picture differs from the screendump, ignoring pixels that change by themselves
    (clock seconds): those differ between two screendumps taken in a row. -1 = too many unstable pixels, -2 = size mismatch."""
    # the VNC picture is read FIRST (before the slow screendumps), so a trailing keep-alive UPDATE cannot repair it meanwhile
    with vnc.lock:
        vw, vh = vnc.w, vnc.h
        buf = bytes(vnc.buf)
    f1 = mon.dump("%s.a.ppm" % base)
    f2 = mon.dump("%s.b.ppm" % base)
    try:
        w, h, b1 = ppm_rgb(f1)
        w2, h2, b2 = ppm_rgb(f2)
    except Exception:
        return -1
    if (vw, vh) != (w, h) or (w2, h2) != (w, h):
        return -2
    v = np.frombuffer(buf, dtype=np.uint8).reshape(h, w, 4)[:, :, [2, 1, 0]]
    d1 = np.frombuffer(b1, dtype=np.uint8).reshape(h, w, 3)
    d2 = np.frombuffer(b2, dtype=np.uint8).reshape(h, w, 3)
    unstable = np.any(d1 != d2, axis=2)
    if int(unstable.sum()) > (w * h) // 50:
        return -1
    bad = np.any(v != d1, axis=2) & ~unstable
    diff = int(bad.sum())
    if diff:
        np.save("%s.%s.vnc.npy" % (base, tag), v)
        np.save("%s.%s.dump.npy" % (base, tag), d1)
        np.save("%s.%s.bad.npy" % (base, tag), bad)
    return diff


def main():
    mon = Mon(mon_sock)
    rng = random.Random(seed)
    vnc = Vnc(vnc_sock)
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
    time.sleep(settle)  # desktop comes up, heal stages and the trailing UPDATE are over
    out = open(base + ".rounds", "w")
    out.write("0 %d\n" % compare(mon, vnc, "r0"))
    out.flush()
    keys = list("abcdefghijklmnopqrstuvwxyz") + ["spc", "tab", "esc", "meta_l", "ret", "backspace"]
    for i in range(1, rounds + 1):
        for _ in range(rng.randint(10, 18)):
            r = rng.random()
            if r < 0.55:
                mon.cmd("mouse_move %d %d" % (rng.randint(-260, 260), rng.randint(-200, 200)), 0.08)
            elif r < 0.78:
                mon.cmd("mouse_button 1", 0.08)
                mon.cmd("mouse_button 0", 0.15)
            else:
                mon.cmd("sendkey " + rng.choice(keys), 0.1)
        time.sleep(0.7)  # shorter than the 2 s trailing UPDATE: a lost rectangle must still be visible here
        out.write("%d %d\n" % (i, compare(mon, vnc, "r%d" % i)))
        out.flush()
    out.close()
    with vnc.lock:
        n = vnc.updates
    open(base + ".updates", "w").write(str(n))
    vnc.stop = True
    mon.quit()


main()
