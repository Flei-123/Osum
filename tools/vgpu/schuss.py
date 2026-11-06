#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    shot.py <monitor-socket> <target.ppm> [wartesekunden] [device]
"""
import os
import socket
import sys
import time


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    sock, target = sys.argv[1], sys.argv[2]
    deadline = float(sys.argv[3]) if len(sys.argv) > 3 else 15.0
    device = sys.argv[4] if len(sys.argv) > 4 else ""

    if os.path.exists(target):
        os.unlink(target)
    s = None
    bis = time.time() + deadline
    while time.time() < bis:
        try:
            s = socket.socket(socket.AF_UNIX)
            s.connect(sock)
            break
        except OSError:
            s = None
            time.sleep(0.1)
    if s is None:
        print("kein Monitor an %s" % sock)
        return 1
    s.settimeout(5.0)
    time.sleep(0.3)
    try:
        s.recv(65536)
    except OSError:
        pass
    cmd = "screendump %s" % target
    if device:
        cmd += " %s" % device
    s.sendall((cmd + "\n").encode())
    last = -1
    bis = time.time() + deadline
    while time.time() < bis:
        try:
            g = os.path.getsize(target)
        except OSError:
            g = -1
        if g > 0 and g == last:
            break
        last = g
        time.sleep(0.2)
    try:
        s.close()
    except OSError:
        pass
    if not os.path.exists(target) or os.path.getsize(target) == 0:
        print("no image written")
        return 1
    print("%s (%d Oktette)" % (target, os.path.getsize(target)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
