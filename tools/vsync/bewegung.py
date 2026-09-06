#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/vsync/bewegung.py -- FOTOS WAEHREND EINER FENSTERBEWEGUNG.

    bewegung.py <monitor-socket> <zielordner> <n> [abstand_s]

Beim Oeffnen waechst ein Fenster aus AN_SCALE0 (85 Prozent) auf volle
Groesse und wird dabei von durchsichtig nach deckend gemischt.  Das
dauert MOTION_DEF = 120 ms, bei TICK_HZ = 100 also etwa zwoelf
Zwischenbilder.

Damit man das MESSEN kann und nicht nur behaupten, holt dieses Programm
in dichter Folge Fotos und schreibt sie weg.  `wachstum.py` rechnet
danach aus, wie gross die farbige Flaeche in jedem Bild war -- waechst
sie ueber die Serie hinweg, hat es eine Bewegung gegeben; springt sie
von nichts auf alles, gab es keine.

Kein Klick und keine Maus: die Vorfuehrung laeuft im Kernel (`wmanim`,
siehe `kgui.anim_vorfuehrung`) zu festen Ticks ab.  Dieses Programm
sieht nur zu.
"""
import os
import socket
import sys
import time


def verbinden(pfad, frist=15.0):
    bis = time.time() + frist
    while time.time() < bis:
        try:
            s = socket.socket(socket.AF_UNIX)
            s.settimeout(5.0)
            s.connect(pfad)
            return s
        except OSError:
            time.sleep(0.1)
    return None


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    sock, ordner, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
    abstand = float(sys.argv[4]) if len(sys.argv) > 4 else 0.03
    os.makedirs(ordner, exist_ok=True)

    s = verbinden(sock)
    if s is None:
        print("kein Monitor an %s" % sock)
        return 1
    time.sleep(0.2)
    try:
        s.recv(65536)
    except OSError:
        pass

    for i in range(n):
        ziel = os.path.join(ordner, "b%03d.ppm" % i)
        if os.path.exists(ziel):
            os.unlink(ziel)
        s.sendall(("screendump %s\n" % ziel).encode())
        try:
            s.recv(65536)
        except OSError:
            pass
        time.sleep(abstand)

    # Halbe Dateien wegwerfen -- siehe schuesse.py.
    gut = 0
    for i in range(n):
        ziel = os.path.join(ordner, "b%03d.ppm" % i)
        letzte = -1
        for _ in range(50):
            try:
                jetzt = os.path.getsize(ziel)
            except OSError:
                jetzt = -1
            if jetzt > 0 and jetzt == letzte:
                break
            letzte = jetzt
            time.sleep(0.02)
        try:
            with open(ziel, "rb") as f:
                kopf = f.read(64)
            if not kopf.startswith(b"P6"):
                os.unlink(ziel)
                continue
            teile = kopf.split()
            w, h = int(teile[1]), int(teile[2])
            versprochen = len(b" ".join(teile[:4])) + 1 + w * h * 3
            if os.path.getsize(ziel) + 8 < versprochen:
                os.unlink(ziel)
                continue
            gut += 1
        except (OSError, ValueError, IndexError):
            try:
                os.unlink(ziel)
            except OSError:
                pass
    print("bilder=%d brauchbar=%d" % (n, gut))
    return 0


if __name__ == "__main__":
    sys.exit(main())
