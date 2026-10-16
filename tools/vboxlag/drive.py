#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/vboxlag/drive.py <monitor-socket> <serial.txt> <outdir> <timeout_s>

Logs in (as tools/inputlogin), then measures the pointer path with F12 between the phases:
  P1 idle, P2 pointer over the desktop (400 small moves), P3 pointer over the taskbar (400 moves),
  P4 a burst of 200 moves with 1 px steps over the desktop, screendump series during P2 (outdir/s*.ppm).
Prints one `PH <name> ...` line per phase with the `wm: bild` and `wm: flush` numbers of that phase.
"""
import re, socket, sys, time

mon, serial, outdir, tmo = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])


def read():
    try:
        with open(serial, "rb") as f:
            return f.read().decode("latin1")
    except OSError:
        return ""


s = None
for _ in range(100):
    try:
        s = socket.socket(socket.AF_UNIX)
        s.connect(mon)
        break
    except OSError:
        time.sleep(0.2)
s.settimeout(3)


def cmd(c, wait=0.12):
    s.sendall((c + "\n").encode())
    time.sleep(wait)
    try:
        s.recv(65536)
    except Exception:
        pass


def move(n, dx, dy, pause=0.0):
    for k in range(n):
        sg = 1 if (k // 20) % 2 == 0 else -1
        s.sendall(("mouse_move %d %d\n" % (sg * dx, sg * dy)).encode())
        if k % 8 == 7:
            try:
                s.recv(65536)
            except Exception:
                pass
        if pause:
            time.sleep(pause)
    time.sleep(0.3)
    try:
        s.recv(65536)
    except Exception:
        pass


def f12():
    cmd("sendkey f12", 0.6)


# The serial lines of several CPUs tear into each other (worst under host load and with the `phases` rect log), so a marker
# line like `glogin: bereit n=` may arrive without its prefix or not at all. Match the tolerant tails and fall back on the
# earlier `glogin: fUi Szenenbaum` line plus a settle time.
READY_MARKS = ("glogin: bereit", "bereit n=")
LOGIN_MARKS = ("angemeldet als", "gemeldet als justin", "glogin: autostart", "glogin: desktop pid", "glogin: uid=")


def seen(marks):
    t = read()
    return any(m in t for m in marks)


t0 = time.time()
ready = 0
fui_at = None
while time.time() - t0 < tmo:
    if seen(READY_MARKS):
        ready = 1
        break
    if fui_at is None and "Szenenbaum" in read():
        fui_at = time.time()
    if fui_at is not None and time.time() - fui_at > 12:
        ready = 1          # screen is up, ready line lost to torn serial output
        break
    time.sleep(1)
if not ready:
    print("RESULT login=0 ready=0")
    sys.exit(1)
def try_login():
    for _ in range(4):
        cmd("mouse_move 30 20")
        time.sleep(0.1)
    time.sleep(1)
    cmd("mouse_button 1")
    time.sleep(0.2)
    cmd("mouse_button 0")
    time.sleep(1)
    for ch in "startkennwort":
        cmd("sendkey " + ch)
        time.sleep(0.1)
    cmd("sendkey ret")
    t1 = time.time()
    while time.time() - t1 < 15:
        if seen(LOGIN_MARKS):
            return True
        time.sleep(1)
    return False


time.sleep(6)
ok = False
for _try in range(4):
    if try_login():
        ok = True
        break
    for _ in range(14):          # clear a half-typed field
        cmd("sendkey backspace", 0.03)
if not ok:
    print("RESULT login=0 ready=1")
    sys.exit(1)
time.sleep(14)           # let the desktop come up (bar, programs)
results = []


def phase(name, action):
    f12()                # reset counters (its own print is dropped)
    time.sleep(1.0)
    p0 = len(read())
    t = time.time()
    action()
    dur = time.time() - t
    f12()
    time.sleep(1.5)
    txt = read()[p0:]
    bl = re.findall(r"wm: bild n=(\d+) mittel=(\d+) max=(\d+) ueber16=(\d+)", txt)
    fl = re.findall(r"wm: flush n=(\d+) us=(\d+) max=(\d+) okt=(\d+)", txt)
    n = sum(int(b[0]) for b in bl)
    mean = sum(int(b[0]) * int(b[1]) for b in bl) // max(n, 1)
    mx = max([int(b[2]) for b in bl] or [0])
    o16 = sum(int(b[3]) for b in bl)
    cn = sum(int(f[0]) for f in fl)
    cus = sum(int(f[1]) for f in fl)
    cmx = max([int(f[2]) for f in fl] or [0])
    okt = sum(int(f[3]) for f in fl)
    results.append("PH %-8s secs=%.1f frames=%d mean_us=%d max_us=%d over16=%d | copies=%d copy_us=%d copy_max_us=%d okt=%d okt_per_frame=%d"
                   % (name, dur, n, mean, mx, o16, cn, cus, cmx, okt, okt // max(n, 1)))


def a_idle():
    time.sleep(5)


def a_desktop():
    cmd("mouse_move -300 -300")
    cmd("mouse_move 200 200")
    move(400, 6, 4)


def a_bar():
    for _ in range(10):
        cmd("mouse_move 0 120")
    cmd("mouse_move 100 0")
    move(400, 6, 0)


def a_slow():
    for _ in range(5):
        cmd("mouse_move 0 -120")
    move(200, 1, 1)


phase("idle", a_idle)
phase("desktop", a_desktop)
phase("bar", a_bar)
phase("slow", a_slow)
# final picture (pointer parked at a fixed place): the A/B proof compares it between a normal and a `nodiff` run
cmd("mouse_move -2000 -2000")
cmd("mouse_move 700 300")
time.sleep(1.5)
cmd("screendump %s/final.ppm" % outdir, 1.0)
print("RESULT login=1 ready=1")
for r in results:
    print(r)
