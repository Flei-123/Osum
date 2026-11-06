#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    shutdown3.py -- `shutdown` without Oberflaeche verify: der kuerzeste gone zur
    python3 shutdown3.py
"""
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
D = os.path.join(HIER, "runs", "aus3")


def lauf(name, script, deadline=90):
    d = os.path.join(HIER, "runs", name)
    subprocess.run(["rm", "-rf", d], check=False)
    os.makedirs(d, exist_ok=True)
    ser = os.path.join(d, "serial.txt")
    cmd = ("modfs osum nokbd nosched noproc nofs script=%s" % script)
    open(os.path.join(d, "cmdline.txt"), "w").write(cmd)
    p = subprocess.Popen(
        ["qemu-system-x86_64", "-accel", "kvm", "-cpu", "host",
         "-m", "1024", "-smp", "2",
         "-kernel", os.path.join(HIER, "osum.mb"),
         "-initrd", os.path.join(HIER, "root.img"),
         "-append", cmd, "-display", "none", "-no-reboot",
         "-serial", "file:%s" % ser],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    t0 = time.time()
    while time.time() - t0 < deadline:
        if p.poll() is not None:
            break
        time.sleep(0.5)
    lief = p.poll() is None
    if lief:
        p.kill()
        p.wait()
    txt = ""
    if os.path.exists(ser):
        txt = open(ser, "rb").read().replace(b"\x00", b"").decode(
            "utf-8", "replace")
    return (not lief), round(time.time() - t0, 1), txt, p.returncode


def main():
    print("=== 1. Gegenprobe: laeuft ein Skript ueberhaupt? ===")
    gone, t, txt, rc = lauf("aus3a", "echo HALLO;exit", 60)
    print("   QEMU beendet: %s nach %.1f s (rc=%s)" % (gone, t, rc))
    print("   HALLO im Mitschnitt:", "HALLO" in txt)
    for z in txt.splitlines()[-6:]:
        print("     |", z[:90])

    print("\n=== 2. shutdown ueber init ===")
    gone, t, txt, rc = lauf("aus3b", "shutdown;echo NOCHDA", 90)
    print("   QEMU beendet: %s nach %.1f s (rc=%s)" % (gone, t, rc))
    print("   'NOCHDA' danach:", "NOCHDA" in txt)
    for z in txt.splitlines()[-10:]:
        print("     |", z[:90])

    print("\n=== 3. shutdown -f (ohne init) ===")
    gone_b, t2, txt2, rc2 = lauf("aus3c", "shutdown -f;echo NOCHDA", 90)
    print("   QEMU beendet: %s nach %.1f s (rc=%s)" % (gone_b, t2, rc2))
    print("   'NOCHDA' danach:", "NOCHDA" in txt2)
    for z in txt2.splitlines()[-10:]:
        print("     |", z[:90])

    print("\n=== 4. gibt es /bin/shutdown ueberhaupt? ===")
    gone_c, t3, txt3, rc3 = lauf("aus3d", "ls /bin/shutdown /bin/power;exit", 60)
    for z in txt3.splitlines()[-8:]:
        print("     |", z[:90])
    return 0


if __name__ == "__main__":
    sys.exit(main())
