#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    self2.py -- own-HOSTING auf dem Stick-Abbild, clean gemessen.
    python3 self2.py
"""
import os
import shutil
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HIER, ".."))
MKFS = os.path.join(REPO, "tools", "osum", "mkfs.py")
ARBEIT = "/tmp/ts-selbst"

SOURCE = """fn main() -> i32 {
    return 42
}
"""


def bau_abbild():
    """Das Wurzelabbild der Runde + die Quelle darin."""
    os.makedirs(ARBEIT, exist_ok=True)
    q = os.path.join(ARBEIT, "probe.fi")
    open(q, "w").write(SOURCE)
    # Die vorhandene Wurzel auslesen und mit der Quelle neu bauen waere
    # aufwaendig; mkfs.py kann eine Datei aber auch NACHTRAGEN.
    target = os.path.join(ARBEIT, "root.img")
    shutil.copy(os.path.join(HIER, "root.img"), target)
    r = subprocess.run(["python3", MKFS, "add", target, "/probe.fi=%s" % q],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("mkfs add ging nicht:", (r.stdout + r.stderr)[:400])
        return None
    return target


def lauf(name, root, script, deadline=400):
    d = os.path.join(HIER, "runs", name)
    subprocess.run(["rm", "-rf", d], check=False)
    os.makedirs(d, exist_ok=True)
    ser = os.path.join(d, "serial.txt")
    cmd = "modfs osum nokbd nosched noproc nofs script=%s" % script
    open(os.path.join(d, "cmdline.txt"), "w").write(cmd)
    p = subprocess.Popen(
        ["qemu-system-x86_64", "-accel", "kvm", "-cpu", "host",
         "-m", "2048", "-smp", "2",
         "-kernel", os.path.join(HIER, "osum.mb"),
         "-initrd", root, "-append", cmd,
         "-display", "none", "-no-reboot", "-serial", "file:%s" % ser],
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


def main():
    root = bau_abbild()
    if not root:
        return 1
    print("Abbild mit Quelle: %s (%d Oktette)"
          % (root, os.path.getsize(root)))

    script = ("cat /probe.fi;"
              "firnc /probe.fi -o /probe.s;echo UEB=$?;"
              "fas /probe.s -o /probe;echo BIN=$?;"
              "/probe;echo LAUF=$?;exit")
    txt, t = lauf("selbst2", root, script, 600)
    print("Dauer %.1f s\n" % t)
    for z in txt.splitlines():
        if (z.startswith("osum$") or "UEB=" in z or "BIN=" in z
                or "LAUF=" in z or "fn main" in z or "return" in z
                or "error" in z.lower() or "firnc" in z or "fas" in z):
            print("  |", z[:110])
    print()
    for mark, was in (("UEB=0", "firnc hat uebersetzt"),
                       ("BIN=0", "fas hat gebunden"),
                       ("LAUF=42", "das Programm lief und gab 42")):
        print("  %-9s %-28s %s" % (mark, was, "JA" if mark in txt else "NEIN"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
