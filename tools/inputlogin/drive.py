#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/inputlogin/drive.py <monitor-socket> <serial.txt> <timeout_s>

Waits for the sign-in screen, moves the pointer, types the start password with
sendkey and presses Enter. Prints one line: RESULT login=<0|1> keys=<n> ready=<0|1>.
login=1 when the serial line `glogin: angemeldet als` shows up.
"""
import socket
import sys
import time

mon, serial, tmo = sys.argv[1], sys.argv[2], int(sys.argv[3])


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
s.settimeout(2)


def cmd(c):
    s.sendall((c + "\n").encode())
    time.sleep(0.12)
    try:
        s.recv(65536)
    except Exception:
        pass


t0 = time.time()
ready = 0
while time.time() - t0 < tmo:
    if "glogin: bereit" in read():
        ready = 1
        break
    time.sleep(1)
if ready:
    time.sleep(4)
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
    while time.time() - t1 < 40:
        if "glogin: angemeldet als" in read():
            break
        time.sleep(1)
txt = read()
print("RESULT login=%d keys=%d ready=%d" % (
    1 if "glogin: angemeldet als" in txt else 0, txt.count("\nkey: "), ready))
