#!/usr/bin/env python3
"""tools/wm/monitor.py -- Maus und Tastatur von aussen in die Maschine.

    monitor.py <monitor-socket> <befehlsdatei> [pause]

Runde K7 hat ueber den QEMU-Monitor Bildschirmfotos geholt
(`tools/gfx/screenshot.py`).  Runde K10 braucht denselben Weg in die andere
Richtung: ein Fensterserver, der nie eine Maus gesehen hat, ist nicht
gemessen.  Der Monitor kann das:

    mouse_move <dx> <dy>     eine RELATIVE Bewegung -- das PS/2-Geraet
                             kennt nichts anderes, es schickt
                             Unterschiede, keine Orte.
    mouse_button <maske>     1 = links, 2 = Mitte, 4 = rechts
    sendkey <taste>          ein Tastendruck samt Loslassen

WARUM DIE BEWEGUNGEN KLEIN SIND UND WARUM ES ERST IN DIE ECKE GEHT.
Ein PS/2-Paket traegt neun Bit je Achse; QEMU zerlegt groessere
Bewegungen in mehrere Pakete, und geht dabei eines verloren, ist der
Endpunkt ein anderer.  Ein Testlauf, der auf einen BILDPUNKT genau
rechnen will, faehrt deshalb zuerst mit mehreren grossen Schritten in
die linke obere Ecke -- dort haelt der Anschlag, und die Vorgeschichte
ist geloescht -- und danach mit Schritten unter 128 an die Stelle, die
er meint.  Von da an ist der Ort eine Rechnung und keine Hoffnung.

Zeilen, die mit `#` anfangen, sind Anmerkungen.  `warte <sekunden>`
haelt zwischendurch an.
"""
import socket
import sys
import time


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    sock, datei = sys.argv[1], sys.argv[2]
    pause = float(sys.argv[3]) if len(sys.argv) > 3 else 0.10

    s = None
    bis = time.time() + 15.0
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
        for zeile in open(datei):
            zeile = zeile.strip()
            if not zeile or zeile.startswith("#"):
                continue
            if zeile.startswith("warte"):
                time.sleep(float(zeile.split()[1]))
                continue
            s.sendall((zeile + "\n").encode())
            n += 1
            time.sleep(pause)
            try:
                s.recv(65536)
            except OSError:
                pass
        # Der Maschine Zeit lassen, das Letzte zu verarbeiten, BEVOR
        # fotografiert wird -- sonst misst das Foto einen Zustand, den es
        # noch gar nicht gibt.
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
