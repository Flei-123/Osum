#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""aus3.py -- `shutdown` OHNE Oberflaeche pruefen: der kuerzeste Weg zur
Antwort auf "schaltet die Maschine wirklich ab?".

    python3 aus3.py

WARUM SO. Der Weg ueber das Terminalfenster hat in dieser Runde eine
Stunde gekostet und am Ende nicht die Frage beantwortet, sondern eine
zweite gestellt (welche Schrift malt dort, wie liegt das Raster, was
ueberdeckt die Messtafel). Das ist der Punkt, an dem man den Aufbau
wechselt statt ihn zu retten.

Der Kern kann ein Skript ausfuehren: `script=<befehle>` auf der
Kommandozeile, getrennt durch Semikolon -- derselbe Weg, den
`tools/k16/run.sh` fuer den Uebersetzer benutzt. Damit laeuft
`shutdown` in einer Shell, deren Ausgabe auf der SERIELLEN LEITUNG
steht, und die Frage ist in zwanzig Sekunden beantwortet.

Gemessen wird zweierlei:
  1. Was `shutdown` selbst sagt (seine Fehlermeldungen stehen in
     kernel/user/shutdown.fi).
  2. Ob der QEMU-Prozess verschwindet. Eine ACPI-Abschaltung beendet
     ihn; mit `-no-reboot` kommt er nicht zurueck.
"""
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
D = os.path.join(HIER, "laeufe", "aus3")


def lauf(name, script, frist=90):
    d = os.path.join(HIER, "laeufe", name)
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
    while time.time() - t0 < frist:
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
    weg, t, txt, rc = lauf("aus3a", "echo HALLO;exit", 60)
    print("   QEMU beendet: %s nach %.1f s (rc=%s)" % (weg, t, rc))
    print("   HALLO im Mitschnitt:", "HALLO" in txt)
    for z in txt.splitlines()[-6:]:
        print("     |", z[:90])

    print("\n=== 2. shutdown ueber init ===")
    weg, t, txt, rc = lauf("aus3b", "shutdown;echo NOCHDA", 90)
    print("   QEMU beendet: %s nach %.1f s (rc=%s)" % (weg, t, rc))
    print("   'NOCHDA' danach:", "NOCHDA" in txt)
    for z in txt.splitlines()[-10:]:
        print("     |", z[:90])

    print("\n=== 3. shutdown -f (ohne init) ===")
    weg2, t2, txt2, rc2 = lauf("aus3c", "shutdown -f;echo NOCHDA", 90)
    print("   QEMU beendet: %s nach %.1f s (rc=%s)" % (weg2, t2, rc2))
    print("   'NOCHDA' danach:", "NOCHDA" in txt2)
    for z in txt2.splitlines()[-10:]:
        print("     |", z[:90])

    print("\n=== 4. gibt es /bin/shutdown ueberhaupt? ===")
    weg3, t3, txt3, rc3 = lauf("aus3d", "ls /bin/shutdown /bin/power;exit", 60)
    for z in txt3.splitlines()[-8:]:
        print("     |", z[:90])
    return 0


if __name__ == "__main__":
    sys.exit(main())
