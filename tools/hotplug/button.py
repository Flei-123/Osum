#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HIER))
sys.path.insert(0, os.path.join(ROOT, "pruef"))
from click_driver import Maschine  # noqa: E402

ARB = sys.argv[1]
AUS = sys.argv[2]
WIDE, UP = 1024, 768
SER = os.path.join(ARB, "knopf-seriell.txt")
SOCK = os.path.join(ARB, "knopf.sock")
os.makedirs(AUS, exist_ok=True)
for f in (SER, SOCK):
    if os.path.exists(f):
        os.unlink(f)

befund = []


def say(*a):
    t = " ".join(str(x) for x in a)
    print("  " + t, flush=True)
    befund.append(t)


def read_2():
    try:
        return open(SER, "rb").read().decode("utf-8", "replace")
    except OSError:
        return ""


def wait_auf(muster, limit=120.0, was=""):
    t0 = time.time()
    while time.time() - t0 < limit:
        if re.search(muster, read_2()):
            say("gesehen: %s (%.0fs)" % (was or muster, time.time() - t0))
            return True
        if p.poll() is not None:
            say("QEMU exited early, rc=%s" % p.returncode)
            return False
        time.sleep(0.5)
    say("NOT seen: %s" % (was or muster))
    return False


APP = ("gfx wm wigfiles wmshell wmdauer herz hidgen "
       "nosched noproc nofs usb vfs fbres=%dx%d" % (WIDE, UP))
kvm = (["-accel", "kvm", "-cpu", "host"] if os.access("/dev/kvm", os.W_OK)
       else ["-accel", "tcg"])
q = ["qemu-system-x86_64"] + kvm + [
    "-kernel", os.path.join(ARB, "k.mb"), "-m", "512",
    "-append", APP, "-display", "none", "-no-reboot", "-vga", "std",
    "-serial", "file:" + SER,
    "-monitor", "unix:%s,server,nowait" % SOCK,
    "-drive", "file=%s,format=raw,if=ide,index=0" % os.path.join(ARB, "live-knopf.img"),
    "-device", "qemu-xhci,id=xhci",
    "-device", "usb-mouse", "-device", "usb-kbd",
    "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04",
]
p = subprocess.Popen(q, stdout=open(os.path.join(ARB, "knopf-qemu.log"), "w"),
                     stderr=subprocess.STDOUT)
say("QEMU pid=%d" % p.pid)

rc = 1
try:
    if not wait_auf(r"wlib: win id=\d+ x=\d+ y=\d+ w=\d+ h=\d+", 180,
                     "das Fenster des Dateimanagers steht"):
        raise SystemExit(1)
    if not wait_auf(r"explorer: places n=\d+", 120, "die Seitenleiste steht"):
        raise SystemExit(1)
    time.sleep(6)

    m = Maschine(SOCK, WIDE, UP)
    m.verbinde()
    m.photo(os.path.join(ARB, "10-ohne.ppm"))
    say("Image 1: the bar without stick")

    vor = len(re.findall(r"explorer: places n=(\d+) carrier=(\d+)", read_2()))

    m.say("drive_add 0 id=stk,if=none,file=%s,format=raw"
          % os.path.join(ARB, "stick.img"))
    m.say("device_add usb-storage,id=devstk,drive=stk,bus=xhci.0")
    say("Stick gesteckt (device_add usb-storage)")
    if not wait_auf(r"wechsel: kommt", 90, "der Kern haengt ihn ein"):
        raise SystemExit(1)

    got = False
    t0 = time.time()
    while time.time() - t0 < 60:
        tr = re.findall(r"explorer: places n=\d+ carrier=(\d+)", read_2())
        if tr and int(tr[-1]) >= 1:
            got = True
            break
        time.sleep(0.5)
    say("Stick in the bar WITHOUT action: %s (carrier=%s)"
        % ("JA" if got else "NEIN", tr[-1] if tr else "?"))
    time.sleep(3)
    m.photo(os.path.join(ARB, "20-steckt.ppm"))
    say("Image 2: the stick is in the bar")

    txt = read_2()
    wins = re.findall(r"wlib: win id=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", txt)
    if not wins:
        say("no file manager window in the report")
        raise SystemExit(1)
    wx, wy, ww, wh = (int(v) for v in wins[-1])
    say("File manager window: x=%d y=%d w=%d h=%d" % (wx, wy, ww, wh))

    rects = re.findall(
        r"explorer: rect id=(\d+) kind=(\d+) x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+)",
        txt)
    if not rects:
        say("NO control reported -- is /etc/uitrace on the disk?")
        raise SystemExit(1)
    say("%d gemeldete Bedienelemente" % len(rects))

    zid = re.findall(r"explorer: ausknopf id=(\d+)", txt)
    target = None
    if zid:
        for r in rects:
            if r[0] == zid[-1]:
                target = r
        say("Auswurfknopf gemeldet als id=%s" % zid[-1])
    if target is None:
        say("the eject button number is not in the capture")
        raise SystemExit(1)

    _id, _k, rx, ry, rw, rh = target
    cx = wx + int(rx) + int(rw) // 2
    cy = wy + int(ry) + int(rh) // 2
    say("Klick auf GEMELDETE Koordinaten: (%d,%d) "
        "[Fenster %d,%d + Rechteck %s,%s %sx%s]"
        % (cx, cy, wx, wy, rx, ry, rw, rh))

    list_2 = None
    oid = re.findall(r"explorer: placelist id=(\d+)", txt)
    if oid:
        for r in rects:
            if r[0] == oid[-1]:
                list_2 = r
    lines = re.findall(r"explorer: ortzeile i=(\d+) y=(-?\d+) h=(\d+)", txt)
    if list_2 is None or not lines:
        say("Place list or carrier line not reported "
            "(liste=%s zeilen=%d)" % (list_2 is not None, len(lines)))
        raise SystemExit(1)
    lx, ly, lw = int(list_2[2]), int(list_2[3]), int(list_2[4])
    zi, zy, zh = (int(v) for v in lines[-1])
    zx = wx + lx + lw // 2
    zyy = wy + ly + zy + zh // 2
    say("Traegerzeile i=%d auswaehlen bei GEMELDETEN (%d,%d)" % (zi, zx, zyy))
    m.klick_auf(zx, zyy)
    time.sleep(2)

    m.klick_auf(cx, cy)
    time.sleep(4)
    if not wait_auf(r"explorer: eject", 30, "der Knopf hat gefeuert"):
        pass
    time.sleep(3)
    m.photo(os.path.join(ARB, "30-ausgeworfen.ppm"))
    say("Image 3: after clicking the eject button")
    rc = 0
finally:
    try:
        p.terminate()
        p.wait(timeout=10)
    except Exception:
        try:
            p.kill()
        except Exception:
            pass

try:
    from PIL import Image
    for n in ("10-ohne", "20-steckt", "30-ausgeworfen"):
        s = os.path.join(ARB, n + ".ppm")
        if os.path.exists(s) and os.path.getsize(s) > 0:
            Image.open(s).save(os.path.join(AUS, n + ".png"))
            say("%s.png (%d Oktette)"
                % (n, os.path.getsize(os.path.join(AUS, n + ".png"))))
except ImportError:
    say("PIL missing -- the PPM files stay")

open(os.path.join(ARB, "knopf-befund.txt"), "w").write("\n".join(befund) + "\n")
sys.exit(rc)
