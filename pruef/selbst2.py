#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""selbst2.py -- SELBST-HOSTING auf dem Stick-Abbild, sauber gemessen.

    python3 selbst2.py

WARUM DIE QUELLE NICHT MIT `echo` GESCHRIEBEN WIRD. Der erste Versuch
tat genau das und ist an der SHELL gescheitert, nicht am Uebersetzer:

    script=echo fn main() -> i32 { return 42 } > /tmp/h.fi
    -> in der Datei stand:  fn main() - { return 42 }

Die Shell hat `> i32` als Umlenkung gelesen (richtig!), und in einem
zweiten Versuch verschluckte sie auch `{ }`. Ein Uebersetzer, dem man
kaputten Text gibt, sagt zu Recht nein -- gemessen haette man dann die
Zitierregeln der Shell und nicht das Selbst-Hosting.

Also wird die Quelle FERTIG ins Abbild gelegt (`mkfs.py`), so wie
`tools/k16/run.sh` es auch macht. Dann steht im Skript nur noch das,
worum es geht: uebersetzen, binden, ausfuehren.
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

QUELLE = """fn main() -> i32 {
    return 42
}
"""


def bau_abbild():
    """Das Wurzelabbild der Runde + die Quelle darin."""
    os.makedirs(ARBEIT, exist_ok=True)
    q = os.path.join(ARBEIT, "probe.fi")
    open(q, "w").write(QUELLE)
    # Die vorhandene Wurzel auslesen und mit der Quelle neu bauen waere
    # aufwaendig; mkfs.py kann eine Datei aber auch NACHTRAGEN.
    ziel = os.path.join(ARBEIT, "root.img")
    shutil.copy(os.path.join(HIER, "root.img"), ziel)
    r = subprocess.run(["python3", MKFS, "add", ziel, "/probe.fi=%s" % q],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("mkfs add ging nicht:", (r.stdout + r.stderr)[:400])
        return None
    return ziel


def lauf(name, wurzel, script, frist=400):
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
    wurzel = bau_abbild()
    if not wurzel:
        return 1
    print("Abbild mit Quelle: %s (%d Oktette)"
          % (wurzel, os.path.getsize(wurzel)))

    script = ("cat /probe.fi;"
              "firnc /probe.fi -o /probe.s;echo UEB=$?;"
              "fas /probe.s -o /probe;echo BIN=$?;"
              "/probe;echo LAUF=$?;exit")
    txt, t = lauf("selbst2", wurzel, script, 600)
    print("Dauer %.1f s\n" % t)
    for z in txt.splitlines():
        if (z.startswith("osum$") or "UEB=" in z or "BIN=" in z
                or "LAUF=" in z or "fn main" in z or "return" in z
                or "error" in z.lower() or "firnc" in z or "fas" in z):
            print("  |", z[:110])
    print()
    for marke, was in (("UEB=0", "firnc hat uebersetzt"),
                       ("BIN=0", "fas hat gebunden"),
                       ("LAUF=42", "das Programm lief und gab 42")):
        print("  %-9s %-28s %s" % (marke, was, "JA" if marke in txt else "NEIN"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
