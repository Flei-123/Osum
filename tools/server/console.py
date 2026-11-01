#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/server/console.py -- ein Mensch an der seriellen Leitung, in
Python.

WARUM DAS EIN EIGENES PROGRAMM IST. Jeder Testlaeufer dieses Projektes
hat die serielle Leitung bisher als EINBAHNSTRASSE benutzt: QEMU mit
`-serial file:`, hinterher `grep`. Diese Runde baut den Rueckweg, und
den kann man mit einer Datei nicht messen -- ein Terminal ist eine
Unterhaltung: warten, bis die Gegenseite fertig ist, dann tippen, dann
wieder warten.

`-serial stdio` mit einer Pipe reicht dafuer nicht. Eine Pipe liefert
alles sofort, und dann steht die halbe Eingabe in der Leitung, bevor
`serial.init` den Baustein ueberhaupt eingestellt hat -- das erste
Oktett faellt aus, weil das Zuruecksetzen der FIFO (FCR 0xC7) es
mitnimmt. Genau das ist beim ersten Lauf passiert: aus `echo hallo`
wurde `cho hallo`. Das ist kein Fehler des Kernels; ein echtes Terminal
verliert dasselbe Oktett, wenn man tippt, bevor die Maschine an ist.

Also: eine UNIX-Steckdose als Leitung, hier lesen und schreiben, und
IMMER erst auf eine Marke warten, bevor etwas hineingeht.

    console.py <socket> <logdatei> --erwarte <text> --sende <zeile> ...

Rueckgabe 0, wenn jede Erwartung eingetroffen ist.
"""
import os
import re
import socket
import sys
import time


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    path_2, log = sys.argv[1], sys.argv[2]
    schritte = []
    args = sys.argv[3:]
    i = 0
    while i < len(args):
        if args[i] in ("--erwarte", "--sende", "--frist", "--roh"):
            schritte.append((args[i], args[i + 1]))
            i += 2
        else:
            print("unbekannt: %s" % args[i])
            return 2

    s = None
    for _ in range(200):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(path_2)
            break
        except OSError:
            s = None
            time.sleep(0.05)
    if s is None:
        print("console: the line %s does not come" % path_2)
        return 1
    s.settimeout(0.2)

    buffer = bytearray()
    error = []
    frist = 40.0

    def read_2(bis):
        ende = time.time() + bis
        while time.time() < ende:
            try:
                d = s.recv(4096)
            except socket.timeout:
                continue
            except OSError:
                break
            if not d:
                break
            buffer.extend(d)
        return buffer

    def wait_auf(muster, bis):
        ende = time.time() + bis
        rx = re.compile(muster.encode(), re.S)
        while time.time() < ende:
            if rx.search(buffer):
                return True
            try:
                d = s.recv(4096)
            except socket.timeout:
                continue
            except OSError:
                return False
            if not d:
                return False
            buffer.extend(d)
        return False

    for art, value in schritte:
        if art == "--frist":
            frist = float(value)
        elif art == "--erwarte":
            if wait_auf(value, frist):
                print("   erwartet und bekommen: %s" % value)
            else:
                error.append(value)
                print("   AUSGEBLIEBEN: %s" % value)
                break
        elif art == "--sende":
            line = value.replace("\\n", "\n").replace("\\t", "\t")
            line = line.replace("\\003", "\003").replace("\\004", "\004")
            line = line.replace("\\025", "\025").replace("\\010", "\010")
            line = line.replace("\\033", "\033")
            for ch in line.encode():
                s.send(bytes([ch]))
                time.sleep(0.002)
        elif art == "--roh":
            s.send(bytes(int(x) for x in value.split(",")))

    read_2(1.0)
    with open(log, "wb") as f:
        f.write(bytes(buffer))
    try:
        s.close()
    except OSError:
        pass
    if error:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
