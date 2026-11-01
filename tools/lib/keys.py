#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    keys.py <monitor.sock> <serielle-file> key [key ...]
    [--ready TEXT] [--elapsed SECS] [--vorlauf SECS]
"""
import os
import re
import socket
import sys
import time

TIME_JE_KEY = 12.0
TIME_READY = 40.0


def rows(path_2):
    try:
        with open(path_2, "rb") as f:
            return f.read().count(b"key: ")
    except OSError:
        return 0


def wait_auf(path_2, text, limit):
    roh = text.encode()
    ende = time.time() + limit
    while time.time() < ende:
        try:
            with open(path_2, "rb") as f:
                if roh in f.read():
                    return True
        except OSError:
            pass
        time.sleep(0.05)
    return False


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    sock = argv[1]
    seriell = argv[2]
    keys_2 = []
    ready = None
    elapsed = TIME_JE_KEY
    vorlauf = 0.4
    i = 3
    while i < len(argv):
        a = argv[i]
        if a == "--ready":
            i += 1
            ready = argv[i]
        elif a == "--elapsed":
            i += 1
            elapsed = float(argv[i])
        elif a == "--vorlauf":
            i += 1
            vorlauf = float(argv[i])
        else:
            keys_2.append(a)
        i += 1

    if ready and not wait_auf(seriell, ready, TIME_READY):
        print("keys: the kernel has '%s' nicht gemeldet" % ready)
        return 1

    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock)
    time.sleep(vorlauf)

    fehlend = []
    for nr, key_2 in enumerate(keys_2, 1):
        vorher = rows(seriell)
        s.sendall(("sendkey %s\n" % key_2).encode())
        begin = time.time()
        ende = begin + elapsed
        angekommen = False
        while time.time() < ende:
            if rows(seriell) > vorher:
                angekommen = True
                break
            time.sleep(0.02)
        dur = time.time() - begin
        if angekommen:
            print("keys: %2d/%d  %-10s arrived after %.2fs"
                  % (nr, len(keys_2), key_2, dur))
        else:
            print("keys: %2d/%d  %-10s NOT arrived (waited %.1fs)"
                  % (nr, len(keys_2), key_2, dur))
            fehlend.append(key_2)
    s.close()

    if fehlend:
        print("keys: %d of %d keys did not arrive: %s"
              % (len(fehlend), len(keys_2), " ".join(fehlend)))
        return 1
    print("keys: all %d keys arrived via IRQ1" % len(keys_2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
