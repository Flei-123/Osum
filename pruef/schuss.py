#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    schuss.py -- EIN run: Schreibtisch hochfahren, bedienen, fotografieren.
    python3 check/schuss.py <name> [drehbuch.py]
"""
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
os.chdir(HIER)
from click_driver import Maschine

# Die Kommandozeile des Kerns. WORTGLEICH aus pruef/oneshot.py, damit
# beide Laeufe denselben Rechner meinen. `fbres` setzt die Aufloesung;
# `desk` startet den Schreibtisch, `wmdauer` laesst den Fensterserver
# laufen statt nach einem Bild stehenzubleiben.
CL = ("modfs osum gfx wm wig desk wmshell wmdauer herz absturzhalt nopuls "
      "tz=120 usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 "
      "nosched noproc nofs fbres=1280x800")

WIDTH, HEIGHT = 1280, 800


class Lauf:
    """Eine laufende Maschine mit Bildablage und Protokoll."""

    def __init__(self, name):
        self.name = name
        self.d = os.path.join(HIER, "laeufe", name)
        self.s = os.path.join(HIER, "shots", name)
        subprocess.run(["rm", "-rf", self.d, self.s])
        os.makedirs(self.d)
        os.makedirs(self.s)
        self.ser = os.path.join(self.d, "serial.txt")
        self.sock = "/tmp/schuss-%s.sock" % name
        if os.path.exists(self.sock):
            os.unlink(self.sock)
        self.log = open(os.path.join(self.d, "befund.txt"), "w", buffering=1)
        self.n = 0
        self.p = None
        self.m = None

    # ---------------------------------------------------------- Protokoll
    def say(self, *a):
        print(*a)
        print(*a, file=self.log)

    def read_text(self):
        """Die serielle Leitung als Text. Sie ist das Protokoll des Kerns."""
        try:
            return open(self.ser, "rb").read().decode("utf-8", "replace")
        except OSError:
            return ""

    def wins(self):
        """Alle Fensterlagen, die der Fensterserver bisher berichtet hat."""
        return re.findall(
            r"wlib: win id=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", self.read_text())

    # ------------------------------------------------------------- Starten
    def start(self, deadline=180):
        kvm = (["-accel", "kvm", "-cpu", "host"]
               if os.access("/dev/kvm", os.W_OK) else ["-accel", "tcg"])
        q = (["qemu-system-x86_64"] + kvm +
             ["-m", "512", "-smp", "2",
              "-kernel", os.path.join(HIER, "osum.mb"),
              "-initrd", os.path.join(HIER, "root.img"),
              "-append", CL, "-vga", "std",
              "-device", "qemu-xhci,id=xhci",
              # RELATIVE Maus: click_driver.py rechnet relativ (siehe dort).
              # Ein Tablet waere absolut und die Rechnung ginge schief.
              "-device", "usb-mouse", "-device", "usb-kbd",
              "-serial", "file:" + self.ser,
              "-monitor", "unix:%s,server,nowait" % self.sock,
              "-display", "none", "-no-reboot"])
        self.p = subprocess.Popen(
            q, stdout=open(os.path.join(self.d, "qemu.txt"), "w"),
            stderr=subprocess.STDOUT)
        self.say("QEMU pid %d (%s)" % (self.p.pid, kvm[1]))
        t0 = time.time()
        # NICHT auf "ready" warten, sondern auf das Fenster des Starters:
        # erst dann steht seine Lage fest (die Lehre aus oneshot.py).
        while time.time() - t0 < deadline:
            if re.search(r"wm: fen .*id=\d+ .*lay=4", self.read_text()) or re.search(r"id=11 x=\d+", self.read_text()):
                break
            if self.p.poll() is not None:
                self.say("QEMU vorzeitig weg rc=%s" % self.p.returncode)
                return False
            time.sleep(0.5)
        else:
            self.say("ABBRUCH: Schreibtisch kam nicht hoch in %ds" % deadline)
            return False
        self.say("Schreibtisch bereit nach %.0fs" % (time.time() - t0))
        time.sleep(3)
        self.m = Maschine(self.sock, WIDTH, HEIGHT)
        self.m.verbinde()
        return True

    # -------------------------------------------------------------- Bilder
    def image(self, title):
        """Ein Bild mit laufender Nummer. Der Titel steht im Dateinamen."""
        self.n += 1
        roh = os.path.join(self.s, "%02d-%s.ppm" % (self.n, title))
        self.m.photo(roh)
        self.say("  [bild %02d] %s" % (self.n, title))
        return roh

    def ende(self):
        if self.p and self.p.poll() is None:
            self.p.kill()
        # PPM -> PNG. Ein PPM ist unkomprimiert und sprengt jedes Repo.
        for f in sorted(os.listdir(self.s)):
            if f.endswith(".ppm"):
                try:
                    from PIL import Image
                    voll = os.path.join(self.s, f)
                    Image.open(voll).save(voll[:-4] + ".png")
                    os.unlink(voll)
                except Exception as e:
                    self.say("  PNG-Wandlung fehlgeschlagen (%s)" % e)
        self.say("Bilder: %s" % self.s)


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "schreibtisch"
    drehbuch = sys.argv[2] if len(sys.argv) > 2 else None
    lauf = Lauf(name)
    if not lauf.start():
        lauf.ende()
        sys.exit(1)
    lauf.image("schreibtisch")
    if drehbuch:
        # Das Drehbuch bekommt `lauf` und macht damit, was es will.
        raum = {"lauf": lauf, "time": time, "re": re}
        with open(drehbuch) as f:
            code = f.read()
        try:
            exec(compile(code, drehbuch, "exec"), raum)
        except Exception:
            import traceback
            lauf.say("DREHBUCH GEFALLEN:\n" + traceback.format_exc())
    lauf.ende()


if __name__ == "__main__":
    main()
