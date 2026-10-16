#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/vboxlag/visual.py <monitor-socket> <serial.txt> <outdir> <timeout_s>

Visual check of the diff flush: logs in, then takes a deterministic screendump series (outdir/v*.ppm) while the pointer is moved over the
desktop, the taskbar and windows (parked in the corner, then moved by a fixed relative path, so two runs are comparable).
tools/vboxlag/visual.sh runs it once normally and once with `nodiff`, then compares the series pixel by pixel.
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


t0 = time.time()
ready = 0
while time.time() - t0 < tmo:
    if "glogin: bereit" in read():
        ready = 1
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
        if "glogin: angemeldet als" in read():
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
n_shot = 0


def shot(tag):
    global n_shot
    cmd("screendump %s/v%02d_%s.ppm" % (outdir, n_shot, tag), 0.9)
    n_shot += 1


def park():
    cmd("mouse_move -1500 -1000", 0.6)   # one big move into the corner (PS/2 clamps)
    time.sleep(0.4)


def go(x, y, tag, sweep=True):
    park()
    if sweep:
        move(120, 5, 3)          # fast sweep to leave trails if any
        park()
    # relative path to (x, y) in chunks
    while x > 0 or y > 0:
        dx, dy = min(x, 40), min(y, 40)
        cmd("mouse_move %d %d" % (dx, dy), 0.12)
        x -= dx
        y -= dy
    time.sleep(0.8)
    shot(tag)


time.sleep(2)
shot("initial")
for i, (x, y) in enumerate([(300, 300), (550, 60), (900, 500), (60, 780), (640, 785), (1200, 300), (20, 20), (1260, 780), (500, 200), (1000, 100)]):
    go(x, y, "p%d" % i)
# open the start menu (win key) and move over it
cmd("sendkey meta_l", 0.9)
time.sleep(1.5)
shot("menu")
go(300, 400, "menu_ptr", sweep=False)
cmd("sendkey esc", 0.5)
time.sleep(1.0)
go(600, 500, "after_menu")
# drag-like fast diagonal sweeps with 1 px steps ending at a fixed place
park()
move(200, 1, 1)
time.sleep(0.8)
shot("slow1px")
park()
time.sleep(1.2)
shot("parked")
print("RESULT login=1 shots=%d" % n_shot)
