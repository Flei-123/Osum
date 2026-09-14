#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/vgpu/schuss.py -- ein Bildschirmfoto von EINEM BESTIMMTEN Geraet.

    schuss.py <monitor-socket> <ziel.ppm> [wartesekunden] [geraet]

Wie tools/gfx/screenshot.py, aber mit dem dritten Argument von
`screendump`: dem Anzeigegeraet. Ohne es nimmt QEMU das erste, und das
ist die VGA-Karte, die es immer dazustellt -- mit einem Grafiktreiber
steht das Bild aber auf der virtio-gpu, und die VGA-Flaeche ist dann
schwarz. Ein Foto davon beweist nichts ueber den Treiber.
"""
import os
import socket
import sys
import time


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    sock, ziel = sys.argv[1], sys.argv[2]
    frist = float(sys.argv[3]) if len(sys.argv) > 3 else 15.0
    geraet = sys.argv[4] if len(sys.argv) > 4 else ""

    if os.path.exists(ziel):
        os.unlink(ziel)
    s = None
    bis = time.time() + frist
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
    befehl = "screendump %s" % ziel
    if geraet:
        befehl += " %s" % geraet
    s.sendall((befehl + "\n").encode())
    # Warten, bis die Datei fertig ist: `screendump` kehrt zurueck,
    # bevor geschrieben wurde.
    letzte = -1
    bis = time.time() + frist
    while time.time() < bis:
        try:
            g = os.path.getsize(ziel)
        except OSError:
            g = -1
        if g > 0 and g == letzte:
            break
        letzte = g
        time.sleep(0.2)
    try:
        s.close()
    except OSError:
        pass
    if not os.path.exists(ziel) or os.path.getsize(ziel) == 0:
        print("kein Bild geschrieben")
        return 1
    print("%s (%d Oktette)" % (ziel, os.path.getsize(ziel)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
