# SPDX-License-Identifier: GPL-2.0-only
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


def stats(vnc):
    with vnc.lock:
        return "upd=%d rects=%d area=%d alive=%d %s" % (vnc.updates, vnc.rects, vnc.area, int(vnc.t.is_alive()), vnc.why.replace(" ", "_"))


def compare(mon, vnc, tag):
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
    if not wait_for(lambda t: "glogin: ready" in t or t.count("glogin: rect id=") >= 3, 200):
        open(base + ".login", "w").write("0")
        mon.quit()
        return
    time.sleep(6)
    for c in "startkennwort":
        mon.cmd("sendkey " + c, 0.12)
    mon.cmd("sendkey ret", 0.3)
    ok = wait_for(lambda t: "glogin: signed in as" in t or "glogin: autostart" in t or "glogin: uid=" in t, 60)
    open(base + ".login", "w").write("1" if ok else "0")
    if not ok:
        mon.quit()
        return
    time.sleep(settle)
    out = open(base + ".rounds", "w")
    out.write("0 %d %s\n" % (compare(mon, vnc, "r0"), stats(vnc)))
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
        time.sleep(0.7)
        out.write("%d %d %s\n" % (i, compare(mon, vnc, "r%d" % i), stats(vnc)))
        out.flush()
        with vnc.lock:
            open(base + ".updates", "w").write(str(vnc.updates))
    out.close()
    with vnc.lock:
        n = vnc.updates
    open(base + ".updates", "w").write(str(n))
    vnc.stop = True
    mon.quit()


main()
