#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    own.py -- own-HOSTING auf dem Stick-Abbild, over den
    python3 own.py
    echo <source> > /tmp/h.fi
"""
import os
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))


def lauf(name, script, deadline=240, mem="2048"):
    d = os.path.join(HIER, "runs", name)
    subprocess.run(["rm", "-rf", d], check=False)
    os.makedirs(d, exist_ok=True)
    ser = os.path.join(d, "serial.txt")
    cmd = "modfs osum nokbd nosched noproc nofs script=%s" % script
    open(os.path.join(d, "cmdline.txt"), "w").write(cmd)
    p = subprocess.Popen(
        ["qemu-system-x86_64", "-accel", "kvm", "-cpu", "host",
         "-m", mem, "-smp", "2",
         "-kernel", os.path.join(HIER, "osum.mb"),
         "-initrd", os.path.join(HIER, "root.img"),
         "-append", cmd, "-display", "none", "-no-reboot",
         "-serial", "file:%s" % ser],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    t0 = time.time()
    while time.time() - t0 < deadline and p.poll() is None:
        time.sleep(0.5)
    if p.poll() is None:
        p.kill()
        p.wait()
    txt = ""
    if os.path.exists(ser):
        txt = open(ser, "rb").read().replace(b"\x00", b"").decode(
            "utf-8", "replace")
    return txt, round(time.time() - t0, 1)


def show(txt, ab="osum$"):
    """Nur die Zeilen der Shell, nicht die des Kerns."""
    aus = []
    for z in txt.splitlines():
        if z.startswith("osum$") or any(
                m in z for m in ("UEB=", "BIN=", "LAUF=", "firnc:", "fas:",
                                 "sh:", "not found", "Fehler", "error")):
            aus.append(z)
    return aus


def main():
    print("=== 1. liegen Uebersetzer und Assembler da? ===")
    txt, t = lauf("sh1", "ls /bin/firnc /bin/fas /bin/edit;exit", 90)
    for z in show(txt):
        print("   |", z[:100])

    print("\n=== 2. eine Quelle schreiben und uebersetzen ===")
    source = "fn main() -> i32 { return 42 }"
    script = ("echo %s > /tmp/h.fi;"
              "firnc /tmp/h.fi -o /tmp/h.s;echo UEB=$?;"
              "fas /tmp/h.s -o /tmp/h;echo BIN=$?;"
              "/tmp/h;echo LAUF=$?;exit") % source
    txt, t = lauf("sh2", script, 300)
    print("   (%.1f s)" % t)
    for z in show(txt):
        print("   |", z[:100])
    for mark in ("UEB=0", "BIN=0", "LAUF=42"):
        print("   %-8s %s" % (mark, "JA" if mark in txt else "NEIN"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
