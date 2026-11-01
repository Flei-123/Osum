#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    keys.py <monitor-socket> <wait-auf-file> <muster> <key> ...
"""
import os
import socket
import sys
import time

EINFACH = {
    ' ': 'spc', '\n': 'ret', '\t': 'tab',
    '-': 'minus', '=': 'equal', '[': 'bracket_left', ']': 'bracket_right',
    ';': 'semicolon', "'": 'apostrophe', '`': 'grave_accent',
    '\\': 'backslash', ',': 'comma', '.': 'dot', '/': 'slash',
}
UMSCHALT = {
    '!': '1', '@': '2', '#': '3', '$': '4', '%': '5', '^': '6', '&': '7',
    '*': '8', '(': '9', ')': '0', '_': 'minus', '+': 'equal',
    '{': 'bracket_left', '}': 'bracket_right', ':': 'semicolon',
    '"': 'apostrophe', '~': 'grave_accent', '|': 'backslash',
    '<': 'comma', '>': 'dot', '?': 'slash',
}


def keys_for(text):
    aus = []
    for c in text:
        if c.islower() or c.isdigit():
            aus.append(c)
        elif c.isupper():
            aus.append('shift-' + c.lower())
        elif c in EINFACH:
            aus.append(EINFACH[c])
        elif c in UMSCHALT:
            aus.append('shift-' + UMSCHALT[c])
        else:
            raise SystemExit("keys.py: fuer %r gibt es keine Taste" % c)
    return aus


def key_lines(path_2):
    try:
        with open(path_2, 'rb') as f:
            return f.read().count(b'key: ')
    except OSError:
        return 0


TIME_JE_KEY = 8.0


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    sock, wait, muster = sys.argv[1], sys.argv[2], sys.argv[3]
    seq = []
    for t in sys.argv[4:]:
        if t.startswith('text:'):
            seq += keys_for(t[5:])
        else:
            seq.append(t)

    bis = time.time() + 60
    ready = False
    while time.time() < bis:
        try:
            with open(wait, 'rb') as f:
                if muster.encode() in f.read():
                    ready = True
                    break
        except OSError:
            pass
        time.sleep(0.2)
    if not ready:
        print("keys.py: '%s' ist nie in %s aufgetaucht" % (muster, wait))
        return 1

    s = None
    bis = time.time() + 30
    while time.time() < bis:
        try:
            s = socket.socket(socket.AF_UNIX)
            s.settimeout(5.0)
            s.connect(sock)
            break
        except OSError:
            s = None
            time.sleep(0.2)
    if s is None:
        print("keys.py: kein Monitor an %s" % sock)
        return 1
    time.sleep(0.3)
    try:
        s.recv(65536)
    except OSError:
        pass
    for k in seq:
        if k.startswith('foto:'):
            target = k[5:]
            if os.path.exists(target):
                os.unlink(target)
            time.sleep(1.2)
            try:
                with open(wait, 'rb') as f:
                    open(target + '.ser', 'wb').write(f.read())
            except OSError:
                pass
            s.sendall(("screendump %s\n" % target).encode())
            last = -1
            ruhig = 0
            bis2 = time.time() + 20
            while time.time() < bis2:
                time.sleep(0.15)
                try:
                    now = os.path.getsize(target)
                except OSError:
                    continue
                if now == last and now > 0:
                    ruhig += 1
                    if ruhig >= 3:
                        break
                else:
                    ruhig = 0
                    last = now
            try:
                s.recv(65536)
            except OSError:
                pass
            continue
        if k.startswith('warte:'):
            time.sleep(float(k[6:]))
            continue
        if k == 'ruhe':
            last = -1
            while True:
                time.sleep(0.4)
                try:
                    now = os.path.getsize(wait)
                except OSError:
                    break
                if now == last:
                    break
                last = now
            continue
        if k.startswith('nowait:'):
            s.sendall(("sendkey %s\n" % k[7:]).encode())
            time.sleep(0.3)
            try:
                s.recv(65536)
            except OSError:
                pass
            continue
        vorher = key_lines(wait)
        s.sendall(("sendkey %s\n" % k).encode())
        bis3 = time.time() + TIME_JE_KEY
        while time.time() < bis3:
            if key_lines(wait) > vorher:
                break
            time.sleep(0.02)
        try:
            s.recv(65536)
        except OSError:
            pass
    time.sleep(0.5)
    s.close()
    print("%d Tasten geschickt" % len(seq))
    return 0


if __name__ == '__main__':
    sys.exit(main())
