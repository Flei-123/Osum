#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    monitor.py <monitor-socket> <serielle-file> <drehbuch>
    device_add usb-storage,id=<name>,drive=<laufwerk>
    device_del <name>
    stecke <id> <file>   einen Stick anstecken (drive + device_add)
    wait <secs>      anhalten
    monitor <roh>         irgendein Monitorbefehl, roh
"""
import os
import socket
import sys
import time

EINFACH = {
    ' ': 'spc', '\n': 'ret', '\t': 'tab', '-': 'minus', '=': 'equal',
    '/': 'slash', '.': 'dot', ',': 'comma', ';': 'semicolon',
    "'": 'apostrophe', '\\': 'backslash', '[': 'bracket_left',
    ']': 'bracket_right', '`': 'grave_accent',
}
SHIFT = {
    '_': 'minus', '+': 'equal', ':': 'semicolon', '"': 'apostrophe',
    '?': 'slash', '<': 'comma', '>': 'dot', '|': 'backslash',
    '!': '1', '@': '2', '#': '3', '$': '4', '%': '5', '^': '6',
    '&': '7', '*': '8', '(': '9', ')': '0', '~': 'grave_accent',
}


class Mon:
    def __init__(self, path_2):
        self.s = None
        bis = time.time() + 20.0
        while time.time() < bis:
            try:
                s = socket.socket(socket.AF_UNIX)
                s.settimeout(5.0)
                s.connect(path_2)
                self.s = s
                break
            except OSError:
                time.sleep(0.1)
        if self.s is None:
            raise SystemExit("kein Monitor an %s" % path_2)
        time.sleep(0.3)
        self.clear()

    def clear(self):
        self.s.settimeout(0.4)
        try:
            while True:
                if not self.s.recv(65536):
                    break
        except OSError:
            pass

    def tu(self, cmd_2):
        self.s.sendall((cmd_2 + "\n").encode())
        time.sleep(0.12)
        self.clear()


def keys_for(char):
    if char in EINFACH:
        return [EINFACH[char]]
    if char in SHIFT:
        return ["shift-" + SHIFT[char]]
    if char.isdigit() or (char.isalpha() and char.islower()):
        return [char]
    if char.isalpha() and char.isupper():
        return ["shift-" + char.lower()]
    return []


def wait_auf(file, muster, limit=60.0):
    bis = time.time() + limit
    muster_b = muster.encode()
    while time.time() < bis:
        try:
            with open(file, "rb") as f:
                if muster_b in f.read():
                    return True
        except OSError:
            pass
        time.sleep(0.15)
    return False


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    sock, seriell, drehbuch = sys.argv[1], sys.argv[2], sys.argv[3]
    m = Mon(sock)
    n_ok = 0
    n_bad = 0
    with open(drehbuch) as f:
        lines = f.read().splitlines()
    for roh in lines:
        z = roh.strip()
        if not z or z.startswith("#"):
            continue
        parts = z.split()
        cmd = parts[0]
        if cmd == "stecke":
            ident, file = parts[1], parts[2]
            m.tu("drive_add 0 id=%s,if=none,file=%s,format=raw" % (ident, file))
            m.tu("device_add usb-storage,id=dev%s,drive=%s" % (ident, ident))
            print("   stecke %s (%s)" % (ident, file))
        elif cmd == "ziehe":
            ident = parts[1]
            m.tu("device_del dev%s" % ident)
            print("   ziehe %s" % ident)
        elif cmd == "warte":
            time.sleep(float(parts[1]))
        elif cmd == "aufzeile":
            muster = z.split(None, 1)[1]
            if wait_auf(seriell, muster):
                print("   gesehen: %s" % muster)
                n_ok += 1
            else:
                print("   NOT SEEN (60 s): %s" % muster)
                n_bad += 1
        elif cmd == "foto":
            target = parts[1]
            m.tu("screendump %s" % target)
            bis = time.time() + 20.0
            last = -1
            while time.time() < bis:
                try:
                    now = os.path.getsize(target)
                except OSError:
                    now = -1
                if now > 0 and now == last:
                    break
                last = now
                time.sleep(0.25)
            print("   foto %s (%s Oktette)"
                  % (target, os.path.getsize(target) if os.path.exists(target) else "keine"))
        elif cmd == "taste":
            m.tu("sendkey %s" % parts[1])
        elif cmd == "text":
            for c in z.split(None, 1)[1]:
                for t in keys_for(c):
                    m.tu("sendkey %s" % t)
        elif cmd == "maus":
            m.tu("mouse_move %s %s" % (parts[1], parts[2]))
        elif cmd == "klick":
            m.tu("mouse_button 1")
            time.sleep(0.15)
            m.tu("mouse_button 0")
        elif cmd == "monitor":
            m.tu(z.split(None, 1)[1])
        else:
            print("   unbekannter Befehl: %s" % z)
            n_bad += 1
    print("monitor: %d expected lines seen, %d not" % (n_ok, n_bad))
    return 1 if n_bad else 0


if __name__ == "__main__":
    sys.exit(main())
