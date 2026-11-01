#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    monitor.py <monitor-socket> <befehlsdatei> [pause]
    mouse_button <maske>     1 = left, 2 = Mitte, 4 = right
    Lines starting with a hash are notes.  `wait <secs>`
"""
import socket
import sys
import time


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    sock, file = sys.argv[1], sys.argv[2]
    pause = float(sys.argv[3]) if len(sys.argv) > 3 else 0.10

    s = None
    bis = time.time() + 90.0
    while time.time() < bis:
        try:
            s = socket.socket(socket.AF_UNIX)
            s.settimeout(5.0)
            s.connect(sock)
            break
        except OSError:
            s = None
            time.sleep(0.1)
    if s is None:
        print("kein Monitor an %s" % sock)
        return 1
    n = 0
    try:
        time.sleep(0.3)
        try:
            s.recv(65536)
        except OSError:
            pass
        for line in open(file):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("warte"):
                time.sleep(float(line.split()[1]))
                continue
            s.sendall((line + "\n").encode())
            n += 1
            time.sleep(pause)
            try:
                s.recv(65536)
            except OSError:
                pass
        time.sleep(0.6)
    finally:
        try:
            s.close()
        except OSError:
            pass
    print("%d Befehle" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
