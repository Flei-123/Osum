#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    schuesse.py <monitor-socket> <zielordner> <n> [schrittweite]
"""
import os
import socket
import sys
import time


def verbinden(path_2, deadline=15.0):
    bis = time.time() + deadline
    while time.time() < bis:
        try:
            s = socket.socket(socket.AF_UNIX)
            s.settimeout(5.0)
            s.connect(path_2)
            return s
        except OSError:
            time.sleep(0.1)
    return None


def say(s, line):
    s.sendall((line + "\n").encode())
    try:
        s.recv(65536)
    except OSError:
        pass


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    sock, folder, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
    schritt = int(sys.argv[4]) if len(sys.argv) > 4 else 7
    os.makedirs(folder, exist_ok=True)

    s = verbinden(sock)
    if s is None:
        print("kein Monitor an %s" % sock)
        return 1
    time.sleep(0.4)
    try:
        s.recv(65536)
    except OSError:
        pass

    for _ in range(8):
        say(s, "mouse_move -120 -120")
    say(s, "mouse_move 120 52")
    say(s, "mouse_move 120 0")
    say(s, "mouse_move 64 0")
    say(s, "mouse_button 1")

    geschossen = 0
    for i in range(n):
        say(s, "mouse_move %d %d" % (schritt, schritt // 2))
        target = os.path.join(folder, "s%03d.ppm" % i)
        if os.path.exists(target):
            os.unlink(target)
        say(s, 'screendump %s' % target)
        time.sleep(0.02)
        geschossen += 1

    say(s, "mouse_button 0")
    time.sleep(0.5)

    gut = 0
    for i in range(geschossen):
        target = os.path.join(folder, "s%03d.ppm" % i)
        last = -1
        for _ in range(50):
            try:
                now = os.path.getsize(target)
            except OSError:
                now = -1
            if now > 0 and now == last:
                break
            last = now
            time.sleep(0.02)
        try:
            with open(target, "rb") as f:
                header = f.read(64)
            if not header.startswith(b"P6"):
                os.unlink(target)
                continue
            parts = header.split()
            w, h = int(parts[1]), int(parts[2])
            versprochen = len(b" ".join(parts[:4])) + 1 + w * h * 3
            if os.path.getsize(target) + 8 < versprochen:
                os.unlink(target)
                continue
            gut += 1
        except (OSError, ValueError, IndexError):
            try:
                os.unlink(target)
            except OSError:
                pass
    print("schuesse=%d brauchbar=%d" % (geschossen, gut))
    return 0


if __name__ == "__main__":
    sys.exit(main())
