#!/usr/bin/env python3
"""tools/gfx/screenshot.py -- EIN Bildschirmfoto ueber den QEMU-Monitor.

    screenshot.py <monitor-socket> <ziel.ppm> [wartesekunden]

QEMU kann den Inhalt seines Bildschirms als PPM schreiben (`screendump`),
auch mit `-display none`: die Bildflaeche existiert, sie wird nur nicht
angezeigt.  Der Monitor haengt an einem Unix-Socket, weil ein Testlaeufer
sonst nichts hat, woran er ihn fassen koennte.

Der Ablauf ist die eine Stelle, an der man sich vertun kann: `screendump`
kehrt zurueck, BEVOR die Datei fertig geschrieben ist.  Also wird gewartet,
bis die Datei eine Groesse hat, die sich nicht mehr aendert -- ein halb
geschriebenes PPM ist ein Bild, das jeden Vergleich verliert, und zwar
ohne Hinweis darauf, warum.
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

    if os.path.exists(ziel):
        os.unlink(ziel)

    # Auf den Monitor warten: QEMU legt den Socket beim Start an, und der
    # Testlaeufer ruft hier unter Umstaenden frueher.
    s = None
    bis = time.time() + frist
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
            s.recv(65536)  # die Begruessung
        except OSError:
            pass
        s.sendall(("screendump %s\n" % ziel).encode())

        # Warten, bis die Datei steht UND ihre Groesse sich nicht mehr
        # aendert.
        letzte = -1
        ruhig = 0
        bis = time.time() + frist
        while time.time() < bis:
            time.sleep(0.15)
            try:
                jetzt = os.path.getsize(ziel)
            except OSError:
                continue
            if jetzt == letzte and jetzt > 0:
                ruhig += 1
                if ruhig >= 3:
                    print("%d Oktette" % jetzt)
                    return 0
            else:
                ruhig = 0
                letzte = jetzt
        print("das Bildschirmfoto wurde nicht fertig")
        return 1
    finally:
        try:
            s.close()
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
