#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""schuss-konsole.py -- EIN Lauf auf der KONSOLE, ohne Fensterserver.

WARUM ES DAS NEBEN pruef/schuss.py GIBT.
`edit` ist ein TERMINAL-Programm: es malt mit VT100-Fluchtfolgen
(`ESC [ 7 m` und so weiter). Die Konsole des Kerns deutet sie
(kernel/drv/con/ansi.fi); das TERMINALFENSTER des Schreibtischs deutet
sie NICHT -- dort stehen sie als Text auf dem Schirm. GEMESSEN am
19.09.2026, Bild pruef/shots/editor/02-01-editor-offen.png: mitten im
Text steht `[?25l[1;1H[7m`.

Das ist kein Fehler dieser Runde (angefasst wurden nur explorer.fi,
exporte.fi und -- ueber den Merge -- wlib.fi), aber es heisst: der
Editor laesst sich im Fenster nicht sinnvoll fotografieren. Also wird
er dort gemessen, wo auch tools/k11/run.sh ihn misst -- auf der
KONSOLE, gestartet ueber `script=`.

    python3 pruef/schuss-konsole.py <name> "<kommandozeile>" [drehbuch.py]
"""
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
os.chdir(HIER)
from klick import Maschine

BREITE, HOEHE = 720, 400


class Lauf:
    def __init__(self, name, cmdline, marke):
        self.name = name
        self.marke = marke
        self.d = os.path.join(HIER, "laeufe", name)
        self.s = os.path.join(HIER, "shots", name)
        subprocess.run(["rm", "-rf", self.d, self.s])
        os.makedirs(self.d)
        os.makedirs(self.s)
        self.ser = os.path.join(self.d, "serial.txt")
        self.sock = "/tmp/kons-%s.sock" % name
        if os.path.exists(self.sock):
            os.unlink(self.sock)
        self.log = open(os.path.join(self.d, "befund.txt"), "w", buffering=1)
        self.n = 0
        self.p = None
        self.m = None
        self.cmdline = cmdline

    def sag(self, *a):
        print(*a)
        print(*a, file=self.log)

    def lies(self):
        try:
            return open(self.ser, "rb").read().decode("utf-8", "replace")
        except OSError:
            return ""

    def start(self, frist=120):
        kvm = (["-accel", "kvm", "-cpu", "host"]
               if os.access("/dev/kvm", os.W_OK) else ["-accel", "tcg"])
        q = (["qemu-system-x86_64"] + kvm +
             ["-m", "512",
              "-kernel", os.path.join(HIER, "osum.mb"),
              # DIE WURZEL ALS PLATTE, NICHT ALS `-initrd`.
              # `script=` laeuft in der Stufe, die eine Wurzel schon
              # braucht; mit `modfs` als RAM-Platte und `noring3` kam
              # `edit` gar nicht erst zum Zug (gemessen: die serielle
              # Leitung endete bei `kernel: done`, ohne ein einziges
              # `edit:`). tools/k11/run.sh faehrt aus demselben Grund
              # mit `-drive ... if=ide`.
              "-drive", "file=%s,format=raw,if=ide,index=0"
                        % os.path.join(HIER, "konsole.img"),
              "-append", self.cmdline, "-vga", "std",
              "-device", "qemu-xhci,id=xhci", "-device", "usb-kbd",
              "-serial", "file:" + self.ser,
              "-monitor", "unix:%s,server,nowait" % self.sock,
              "-display", "none", "-no-reboot"])
        self.p = subprocess.Popen(
            q, stdout=open(os.path.join(self.d, "qemu.txt"), "w"),
            stderr=subprocess.STDOUT)
        self.sag("QEMU pid %d" % self.p.pid)
        t0 = time.time()
        while time.time() - t0 < frist:
            if re.search(self.marke, self.lies()):
                break
            if self.p.poll() is not None:
                self.sag("QEMU vorzeitig weg rc=%s" % self.p.returncode)
                return False
            time.sleep(0.4)
        else:
            self.sag("ABBRUCH: '%s' kam nicht in %ds" % (self.marke, frist))
            return False
        self.sag("bereit nach %.0fs" % (time.time() - t0))
        time.sleep(1.5)
        self.m = Maschine(self.sock, BREITE, HOEHE)
        self.m.verbinde()
        return True

    def bild(self, titel):
        self.n += 1
        roh = os.path.join(self.s, "%02d-%s.ppm" % (self.n, titel))
        self.m.foto(roh)
        self.sag("  [bild %02d] %s" % (self.n, titel))
        return roh

    def ende(self):
        if self.p and self.p.poll() is None:
            self.p.kill()
        for f in sorted(os.listdir(self.s)):
            if f.endswith(".ppm"):
                try:
                    from PIL import Image
                    voll = os.path.join(self.s, f)
                    Image.open(voll).save(voll[:-4] + ".png")
                    os.unlink(voll)
                except Exception as e:
                    self.sag("  PNG-Wandlung fehlgeschlagen (%s)" % e)
        self.sag("Bilder: %s" % self.s)


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "konsole"
    cmd = (sys.argv[2] if len(sys.argv) > 2 else
           "osum gfx nosched noproc nofs noring3 script=edit /data/t1.txt")
    drehbuch = sys.argv[3] if len(sys.argv) > 3 else None
    marke = os.environ.get("MARKE", "edit: ready")
    lauf = Lauf(name, cmd, marke)
    if not lauf.start():
        lauf.ende()
        sys.exit(1)
    lauf.bild("start")
    if drehbuch:
        raum = {"lauf": lauf, "time": time, "re": re}
        with open(drehbuch) as f:
            code = f.read()
        try:
            exec(compile(code, drehbuch, "exec"), raum)
        except Exception:
            import traceback
            lauf.sag("DREHBUCH GEFALLEN:\n" + traceback.format_exc())
    lauf.ende()


if __name__ == "__main__":
    main()
