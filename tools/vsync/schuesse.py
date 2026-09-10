#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/vsync/schuesse.py -- VIELE FOTOS WAEHREND EINER BEWEGUNG.

    schuesse.py <monitor-socket> <zielordner> <n> [schrittweite]

`tools/gfx/screenshot.py` holt EIN Bild, nachdem alles zur Ruhe
gekommen ist.  Fuer die Zerreissprobe ist genau das die falsche Frage:
gesucht wird der Zustand WAEHREND der Bewegung, und zwar oft genug, um
einen halben Bildaufbau zu erwischen.

Also: das Fenster ziehen und dabei ununterbrochen fotografieren.  Je
Runde ein `mouse_move` und danach sofort ein `screendump` -- ohne die
Wartezeit, mit der `screenshot.py` auf Ruhe wartet.  Wer Reissen finden
will, muss im ungeeignetsten Augenblick hinsehen.

DER ANSCHLAG ZUERST.  Wie in `tools/wm/monitor.py` beschrieben: das
PS/2-Geraet kennt nur Unterschiede.  Also erst mit grossen Schritten in
die linke obere Ecke (dort haelt der Anschlag und die Vorgeschichte ist
geloescht), dann an den Griff des Fensters, Taste runter, und von da an
in kleinen Schritten ziehen.

Ausgabe: der Ordner enthaelt danach s000.ppm ... s<n-1>.ppm.
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


def sagen(s, zeile):
    s.sendall((zeile + "\n").encode())
    try:
        s.recv(65536)
    except OSError:
        pass


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    sock, ordner, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
    schritt = int(sys.argv[4]) if len(sys.argv) > 4 else 7
    os.makedirs(ordner, exist_ok=True)

    s = verbinden(sock)
    if s is None:
        print("kein Monitor an %s" % sock)
        return 1
    time.sleep(0.4)
    try:
        s.recv(65536)
    except OSError:
        pass

    # 1. in die Ecke, damit der Ort danach eine Rechnung ist
    for _ in range(8):
        sagen(s, "mouse_move -120 -120")
    # 2. auf die Titelleiste des Fensters. Es steht bei x=24 y=40 und
    #    ist 564 breit; die Leiste liegt bei y=40..64. Also in die Mitte
    #    der Leiste: (24+280, 40+12) = (304, 52).
    sagen(s, "mouse_move 120 52")
    sagen(s, "mouse_move 120 0")
    sagen(s, "mouse_move 64 0")
    # 3. Taste runter -- ab hier zieht das Fenster mit
    sagen(s, "mouse_button 1")

    geschossen = 0
    for i in range(n):
        # Erst bewegen, dann SOFORT fotografieren. Kein Warten auf Ruhe.
        sagen(s, "mouse_move %d %d" % (schritt, schritt // 2))
        ziel = os.path.join(ordner, "s%03d.ppm" % i)
        if os.path.exists(ziel):
            os.unlink(ziel)
        sagen(s, 'screendump %s' % ziel)
        # Dem Schreiben ein wenig Zeit geben, aber NICHT auf Ruhe
        # warten -- sonst misst man genau den Zustand, den man nicht
        # sucht. Die Datei wird unten auf Vollstaendigkeit geprueft.
        time.sleep(0.02)
        geschossen += 1

    sagen(s, "mouse_button 0")
    time.sleep(0.5)

    # Halbe Dateien wegwerfen: ein PPM, das kuerzer ist als sein Kopf
    # verspricht, ist kein Beweis fuer Reissen, sondern fuer einen
    # zu frueh gelesenen Puffer.
    gut = 0
    for i in range(geschossen):
        ziel = os.path.join(ordner, "s%03d.ppm" % i)
        # Auf eine Groesse warten, die sich nicht mehr aendert.
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
    print("schuesse=%d brauchbar=%d" % (geschossen, gut))
    return 0


if __name__ == "__main__":
    sys.exit(main())
