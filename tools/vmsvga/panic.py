# SPDX-License-Identifier: GPL-2.0-only
# tools/vmsvga/panic.py -- the KERNEL PANIC SCREEN reaches the VMSVGA host (called by tools/vmsvga/panic.sh, r967, 16.10.2026).
#
# usage: panic.py <monitor sock> <vnc sock> <base> <serial file>
# The VNC client connects first (it applies ONLY the rectangles the host was told about). When the kernel reports the forced exception
# (serial "*** EXCEPTION"; the machine starts paused and is continued once the client is connected) the red panic screen is painted into VRAM; after it settled the VNC picture is compared with the screendump
# (which reads VRAM directly). They are equal only if the driver sent an UPDATE for the panic picture: before the fix nothing did, and
# VirtualBox (TRACES=0) kept showing the last picture of the desktop loop.
# Output files: <base>.diff (differing pixels; -1 no dump, -2 size mismatch, -3 no exception seen), <base>.red (panic-red pixels of the
# screendump), <base>.px (pixels of the screendump)
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vnclib import Mon, Vnc, ppm_rgb  # noqa: E402

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
        time.sleep(0.2)
    return False


def put(name, value):
    open("%s.%s" % (base, name), "w").write(str(value))


def main():
    mon = Mon(mon_sock)
    vnc = Vnc(vnc_sock)
    # QEMU runs with -S (paused): the client is connected and has its first picture BEFORE the kernel starts, otherwise it would take
    # the already-panicked VRAM as its very first (full) rectangle and the compare would prove nothing.
    end = time.time() + 10
    while vnc.updates < 1 and time.time() < end:
        time.sleep(0.1)
    mon.cmd("cont", 0.0)
    if not wait_for(lambda t: "*** EXCEPTION" in t, 120):
        put("diff", -3)
        mon.quit()
        return
    # VNC snapshots at growing delays after the exception: shows WHEN the host side learned about the picture
    snaps = []
    t_exc = time.time()
    for delay in (0.1, 0.4, 1.0, 2.0, 3.5, 5.0):
        while time.time() - t_exc < delay:
            time.sleep(0.02)
        with vnc.lock:
            snaps.append((delay, bytes(vnc.buf), vnc.w, vnc.h, vnc.rects))
    # the VNC picture is read FIRST, so nothing sent later can repair it before the compare
    with vnc.lock:
        vw, vh = vnc.w, vnc.h
        buf = bytes(vnc.buf)
        put("rects", vnc.rects)
    f1 = mon.dump(base + ".a.ppm")
    f2 = mon.dump(base + ".b.ppm")
    try:
        w, h, b1 = ppm_rgb(f1)
        w2, h2, b2 = ppm_rgb(f2)
    except Exception:
        put("diff", -1)
        mon.quit()
        return
    if (vw, vh) != (w, h) or (w2, h2) != (w, h):
        put("diff", -2)
        mon.quit()
        return
    v = np.frombuffer(buf, dtype=np.uint8).reshape(h, w, 4)[:, :, [2, 1, 0]]
    d1 = np.frombuffer(b1, dtype=np.uint8).reshape(h, w, 3)
    d2 = np.frombuffer(b2, dtype=np.uint8).reshape(h, w, 3)
    unstable = np.any(d1 != d2, axis=2)
    bad = np.any(v != d1, axis=2) & ~unstable
    red = (d1[:, :, 0] >= 100) & (d1[:, :, 0] <= 160) & (d1[:, :, 1] < 30) & (d1[:, :, 2] < 30)
    tl = []
    for delay, sb, sw, sh, sr in snaps:
        if (sw, sh) != (w, h):
            tl.append("%.1fs:size" % delay)
            continue
        sv = np.frombuffer(sb, dtype=np.uint8).reshape(h, w, 4)[:, :, [2, 1, 0]]
        tl.append("%.1fs:%d(r%d)" % (delay, int(np.any(sv != d1, axis=2).sum()), sr))
    put("timeline", " ".join(tl))
    put("px", w * h)
    put("red", int(red.sum()))
    put("diff", int(bad.sum()))
    vnc.stop = True
    mon.quit()


main()
