#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""selbst3.py -- warum `firnc` auf dem Stick mit 7 abbricht.

selbst2 hat gemessen: `firnc /beispiel/hallo.fi -o /tmp/hallo.s` -> 7.
Der WIRT uebersetzt dieselbe Quelle mit Code 0. Der Unterschied zum
gruenen Pruefstand (tools/k16/run.sh, Abschnitt 4) ist NICHT der
Uebersetzer, sondern der AUFRUF:

    k16:      cd / ; firnc probe.fi > /probe.s
    selbst2:  firnc /beispiel/hallo.fi -o /tmp/hallo.s

Drei Unterschiede auf einmal (relativer statt absoluter Pfad,
Unterverzeichnis, `-o` statt Umlenkung). Dieser Lauf trennt sie:
jede Fassung einzeln, mit eigenem Rueckgabewert.
"""
import os
import shutil
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
QUELLE = "/tmp/usbimg-ts/root.img"


def lauf(name, wurzel, script, frist=600):
    d = os.path.join(HIER, "laeufe", name)
    subprocess.run(["rm", "-rf", d], check=False)
    os.makedirs(d, exist_ok=True)
    ser = os.path.join(d, "serial.txt")
    cmd = "modfs osum nokbd nosched noproc nofs script=%s" % script
    open(os.path.join(d, "cmdline.txt"), "w").write(cmd)
    p = subprocess.Popen(
        ["qemu-system-x86_64", "-accel", "kvm", "-cpu", "host",
         "-m", "2048", "-smp", "2",
         "-kernel", os.path.join(HIER, "osum.mb"),
         "-initrd", wurzel, "-append", cmd,
         "-display", "none", "-no-reboot", "-serial", "file:%s" % ser],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    t0 = time.time()
    while time.time() - t0 < frist and p.poll() is None:
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
    wurzel = "/tmp/ts-selbst3.img"
    shutil.copy(QUELLE, wurzel)
    # Die Quelle zusaetzlich in die WURZEL legen -- dann ist der k16-Fall
    # (relativer Name, kein Unterverzeichnis) ueberhaupt pruefbar.
    q = "/tmp/ts-hallo.fi"
    shutil.copy(os.path.join(os.path.dirname(HIER),
                             "assets/beispiel/hallo.fi"), q)
    r = subprocess.run(["python3", os.path.join(os.path.dirname(HIER),
                                                "tools/osum/mkfs.py"),
                        "add", wurzel, "/probe.fi=%s" % q],
                       capture_output=True, text=True)
    print("mkfs add:", r.returncode, (r.stdout + r.stderr).strip()[:200])

    script = ("cd /;"
              "firnc /beispiel/hallo.fi > /hallo.s;echo UEB=$?;"
              "fas /hallo.s -o /hallo;echo BIN2=$?;"
              "/hallo;echo LAUF42=$?;"
              "ls /;"
              "exit")
    txt, t = lauf("selbst4", wurzel, script, 900)
    print("Dauer %.1f s\n" % t)
    for z in txt.splitlines():
        if (z.startswith("osum$") or "=" in z or "error" in z.lower()):
            print("  |", z[:120])
    return 0


if __name__ == "__main__":
    sys.exit(main())
