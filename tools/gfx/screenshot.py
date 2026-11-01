#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    screenshot.py <monitor-socket> <target.ppm> [wartesekunden]
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

    if os.path.exists(target):
        os.unlink(target)

    s = None
    bis = time.time() + deadline
    while time.time() < bis:
        try:
            s = socket.socket(socket.AF_UNIX)
            s.settimeout(3.0)
            s.connect(sock)
            break
        except OSError:
            s = None
            time.sleep(0.1)
    if s is None:
        print("kein Monitor an %s" % sock)
        return 1

    try:
        time.sleep(0.3)
        try:
            s.recv(65536)
        except OSError:
            pass
        s.sendall(("screendump %s\n" % target).encode())

        last_2 = -1
        ruhig = 0
        bis = time.time() + deadline
        while time.time() < bis:
            time.sleep(0.15)
            try:
                now = os.path.getsize(target)
            except OSError:
                continue
            if now == last_2 and now > 0:
                ruhig += 1
                if ruhig >= 3:
                    print("%d Oktette" % now)
                    return 0
            else:
                ruhig = 0
                last_2 = now
        print("the screenshot was not finished")
        return 1
    finally:
        try:
            s.close()
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
