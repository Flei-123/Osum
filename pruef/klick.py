#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""klick.py -- OrientOS wie ein Mensch bedienen (Runde DURCHKLICK).

    Ein Werkzeug fuer den QEMU-Monitor: Maus an einen ORT fahren,
    klicken, tippen, fotografieren.

WARUM DIE MAUS SO GEFAHREN WIRD.
QEMUs `mouse_move` ueber den Monitor ist RELATIV (PS/2 schickt
Unterschiede, keine Orte).  Der Weg ist deshalb der aus
tools/wm/monitor.py: erst mit mehreren grossen Schritten in die linke
obere Ecke -- dort haelt der Anschlag und die Vorgeschichte ist
geloescht --, danach in Schritten unter 128 an den Zielort.  Von da an
ist der Ort eine Rechnung und keine Hoffnung.

Benutzung als Bibliothek:

    m = Maschine("/pfad/monitor.sock")
    m.gehe(400, 300); m.klick(); m.foto("shots/01.png")
"""
import os
import socket
import subprocess
import sys
import time

# Tastennamen des QEMU-Monitors fuer die Zeichen, die wir tippen.
# Der Monitor kennt nur Tastennamen, keine Zeichen -- also muss die
# Umschrift hier stehen.  DEUTSCHES LAYOUT: die Maschine legt die
# Belegung selbst aus, wir schicken nur die POSITION der Taste.
ZEICHEN = {
    " ": "spc", ".": "dot", ",": "comma", "-": "minus", "/": "slash",
    ";": "semicolon", "'": "apostrophe", "[": "bracket_left",
    "]": "bracket_right", "\\": "backslash", "=": "equal",
    "\n": "ret", "\t": "tab",
}
for c in "abcdefghijklmnopqrstuvwxyz":
    ZEICHEN[c] = c
for c in "0123456789":
    ZEICHEN[c] = c


class Maschine:
    def __init__(self, sock, breite=1280, hoehe=800, pause=0.06):
        self.sockpfad = sock
        self.breite = breite
        self.hoehe = hoehe
        self.pause = pause
        self.x = 0
        self.y = 0
        self.s = None
        self.verbinde()

    def verbinde(self, frist=30.0):
        bis = time.time() + frist
        while time.time() < bis:
            try:
                s = socket.socket(socket.AF_UNIX)
                s.settimeout(5.0)
                s.connect(self.sockpfad)
                self.s = s
                time.sleep(0.3)
                self._leeren()
                return True
            except OSError:
                time.sleep(0.2)
        raise RuntimeError("kein Monitor an %s" % self.sockpfad)

    def _leeren(self):
        try:
            self.s.recv(65536)
        except OSError:
            pass

    def sag(self, zeile, pause=None):
        self.s.sendall((zeile + "\n").encode())
        time.sleep(self.pause if pause is None else pause)
        self._leeren()

    # ------------------------------------------------------------ Maus
    def ecke(self):
        """In die linke obere Ecke fahren -- der Anschlag loescht die
        Vorgeschichte.  Mehrere grosse Schritte, weil ein PS/2-Paket
        neun Bit je Achse traegt."""
        for _ in range(12):
            self.sag("mouse_move -200 -200", 0.02)
        self.x = 0
        self.y = 0
        time.sleep(0.15)

    def gehe(self, x, y):
        """An einen ORT fahren.  Immer ueber die Ecke, damit der Ort
        eine Rechnung ist."""
        x = max(0, min(int(x), self.breite - 1))
        y = max(0, min(int(y), self.hoehe - 1))
        self.ecke()
        dx, dy = x, y
        while dx > 0 or dy > 0:
            sx = min(dx, 100)
            sy = min(dy, 100)
            self.sag("mouse_move %d %d" % (sx, sy), 0.02)
            dx -= sx
            dy -= sy
        self.x, self.y = x, y
        time.sleep(0.25)

    def klick(self, knopf=1):
        self.sag("mouse_button %d" % knopf, 0.12)
        self.sag("mouse_button 0", 0.12)
        time.sleep(0.35)

    def doppelklick(self):
        self.sag("mouse_button 1", 0.05)
        self.sag("mouse_button 0", 0.05)
        self.sag("mouse_button 1", 0.05)
        self.sag("mouse_button 0", 0.05)
        time.sleep(0.4)

    def klick_auf(self, x, y, knopf=1):
        self.gehe(x, y)
        self.klick(knopf)

    def ziehe(self, x1, y1, x2, y2):
        """Druecken, fahren, loslassen -- fuer Fenster verschieben."""
        self.gehe(x1, y1)
        self.sag("mouse_button 1", 0.15)
        dx, dy = x2 - x1, y2 - y1
        schritte = max(abs(dx), abs(dy)) // 60 + 1
        for i in range(schritte):
            sx = dx // schritte
            sy = dy // schritte
            self.sag("mouse_move %d %d" % (sx, sy), 0.05)
        self.sag("mouse_button 0", 0.15)
        self.x, self.y = x2, y2
        time.sleep(0.4)

    # -------------------------------------------------------- Tastatur
    def taste(self, name):
        self.sag("sendkey %s" % name, 0.08)

    def tippe(self, text, pause=0.05):
        """Text tippen.  Grossbuchstaben ueber shift-<taste>.
        Umlaute haben auf DEUTSCHER Tastatur eigene Tasten:
        ae=apostrophe? nein -- QEMU nennt sie nach US-Position:
        oe=semicolon, ae=apostrophe, ue=bracket_left, ss=minus."""
        de = {"ä": "apostrophe", "ö": "semicolon", "ü": "bracket_left",
              "ß": "minus", "Ä": "shift-apostrophe", "Ö": "shift-semicolon",
              "Ü": "shift-bracket_left"}
        for c in text:
            if c in de:
                self.taste(de[c])
            elif c.isupper():
                self.taste("shift-%s" % c.lower())
            elif c in ZEICHEN:
                self.taste(ZEICHEN[c])
            else:
                continue
            time.sleep(pause)

    # ----------------------------------------------------------- Bild
    def foto(self, ziel, frist=30.0):
        """screendump -> PPM -> PNG.  Es wird gewartet, bis die Datei
        eine Groesse hat, die sich nicht mehr aendert: ein halb
        geschriebenes PPM ist ein Bild, das jeden Vergleich verliert."""
        ppm = ziel + ".ppm" if not ziel.endswith(".ppm") else ziel
        if os.path.exists(ppm):
            os.unlink(ppm)
        self.s.sendall(("screendump %s\n" % ppm).encode())
        bis = time.time() + frist
        letzte = -1
        stabil = 0
        while time.time() < bis:
            if os.path.exists(ppm):
                g = os.path.getsize(ppm)
                if g > 0 and g == letzte:
                    stabil += 1
                    if stabil >= 3:
                        break
                else:
                    stabil = 0
                letzte = g
            time.sleep(0.15)
        self._leeren()
        if not os.path.exists(ppm) or os.path.getsize(ppm) == 0:
            return None
        if ziel.endswith(".png"):
            try:
                subprocess.run(["python3", "-c",
                                "from PIL import Image;import sys;"
                                "Image.open(sys.argv[1]).save(sys.argv[2])",
                                ppm, ziel], check=True,
                               capture_output=True, timeout=60)
                os.unlink(ppm)
                return ziel
            except Exception as e:
                return ppm
        return ppm


def main():
    print(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main())
