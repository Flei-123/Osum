#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/toolbench/fahren.py -- EINEN ABLAUF UEBER EINE VERBINDUNG FAHREN.

    drive.py <monitor-socket> <plan.txt> <serial.txt> <ausgabeverzeichnis>

WARUM ES DIESE DATEI GIBT, und die Begruendung ist eine Messung.

Bis hierher hat der Laeufer je Schritt ein eigenes Werkzeug gestartet:
`tools/wm/monitor.py` fuer die Klicks, `tools/gfx/screenshot.py` fuer die
Bilder. Jedes davon macht seine EIGENE Verbindung zum QEMU-Monitor auf.
Der Monitor haengt an `-monitor unix:...,server,nowait`, und genau
daran ist der Ablauf dieser Runde zweimal gescheitert:

    plan: ziel qsfeld -> 1171,786      (kam an)
    plan: foto q01_offen               (kam an)
    plan: ziel kachel 3 -> 1176,507    "kein Monitor an .../mon.sock"

Von aussen sah das aus, als griffe die Trefferpruefung im Gast nicht --
es war eine Verbindung, die nicht wieder aufging. Zwei Nachmittage
Fehlersuche im falschen Ring.

Also: EINE Verbindung fuer den ganzen Ablauf, aufgemacht wenn die
Maschine steht, zugemacht wenn der Plan fertig ist. Klicks und Bilder
gehen durch dieselbe.

DIE SCHRITTE, einer je Zeile:

    warte <sekunden>
    warteauf <regex> <anzahl> <frist>   poll the serial until <anzahl> lines match
    marke <text>              nur in den Ablauf schreiben
    klick <x>,<y>             Zeiger dorthin, druecken, loslassen
    ziel <worte ...>          Stelle aus dem Mitschnitt holen
                              (tools/toolbench/klickplan.py) und klicken
    foto <name>               Bildschirmfoto nach <ausgabe>/<name>.ppm

DER ZEIGER WIRD RELATIV BEWEGT, weil der PS/2-Zeiger nichts anderes
kann: erst mit grossen Schritten in die linke obere Ecke, wo der
Anschlag die Vorgeschichte loescht, dann in Schritten unter 128 an die
gemeinte Stelle. Zwoelf Schritte in die Ecke und nicht sechs -- sechs
mal 120 sind 720 und reichen auf einem 1280 breiten Schirm nicht (auch
das eine Messung, siehe tools/themestore/click.py).
"""
import os
import re
import socket
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))


class Monitor:
    def __init__(self, pfad, frist=20.0):
        self.s = None
        bis = time.time() + frist
        while time.time() < bis:
            try:
                s = socket.socket(socket.AF_UNIX)
                s.settimeout(5.0)
                s.connect(pfad)
                self.s = s
                break
            except OSError:
                time.sleep(0.1)
        if self.s is None:
            raise SystemExit("fahren: kein Monitor an %s" % pfad)
        time.sleep(0.3)
        self.leeren()

    def leeren(self):
        try:
            self.s.recv(65536)
        except OSError:
            pass

    def cmd(self, zeile, pause=0.10):
        self.s.sendall((zeile + "\n").encode())
        time.sleep(pause)
        self.leeren()

    def zeiger(self, x, y):
        for _ in range(12):
            self.cmd("mouse_move -120 -120", 0.03)
        dx, dy = x, y
        while dx > 0 or dy > 0:
            sx, sy = min(dx, 120), min(dy, 120)
            self.cmd("mouse_move %d %d" % (sx, sy), 0.03)
            dx -= sx
            dy -= sy

    def klick(self, x, y):
        self.zeiger(x, y)
        time.sleep(0.4)
        self.cmd("mouse_button 1", 0.15)
        self.cmd("mouse_button 0", 0.15)
        time.sleep(0.6)

    def rklick(self, x, y):
        self.zeiger(x, y)
        time.sleep(0.4)
        self.cmd("mouse_button 2", 0.15)
        self.cmd("mouse_button 0", 0.15)
        time.sleep(0.6)

    def tippe(self, text):
        keys = {" ": "spc", ".": "dot", "-": "minus"}
        for ch in text:
            self.cmd("sendkey %s" % keys.get(ch, ch), 0.15)
        time.sleep(0.6)

    def foto(self, ziel, frist=25.0):
        if os.path.exists(ziel):
            os.unlink(ziel)
        self.cmd("screendump %s" % ziel, 0.2)
        # `screendump` kehrt zurueck, BEVOR die Datei fertig ist. Also
        # warten, bis die Groesse sich nicht mehr aendert -- ein halb
        # geschriebenes PPM verliert jeden Vergleich, und zwar ohne
        # Hinweis darauf, warum.
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
                    return jetzt
            else:
                ruhig = 0
            letzte = jetzt
        return 0


def ziel_einmal(serial, worte):
    r = subprocess.run(["python3", os.path.join(HIER, "klickplan.py"), serial]
                       + worte, capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        return None, (r.stdout + r.stderr).strip()
    return r.stdout.strip(), ""


def ziel_holen(serial, worte, frist=12.0):
    bis = time.time() + frist
    while True:
        p, fehler = ziel_einmal(serial, worte)
        if p is not None or time.time() >= bis:
            return p, fehler
        time.sleep(0.5)


def zaehle(serial, muster):
    try:
        with open(serial, "rb") as f:
            t = f.read().decode("latin1")
    except OSError:
        return 0
    return len(re.findall(muster, t, re.M))


def warte_auf(serial, muster, anzahl, frist):
    bis = time.time() + frist
    while time.time() < bis:
        if zaehle(serial, muster) >= anzahl:
            return True
        time.sleep(0.25)
    return zaehle(serial, muster) >= anzahl


def main(argv):
    if len(argv) < 5:
        print(__doc__)
        return 2
    sock, plan, serial, out = argv[1], argv[2], argv[3], argv[4]
    m = Monitor(sock)
    for roh in open(plan, encoding="utf-8"):
        z = roh.strip()
        if not z or z.startswith("#"):
            continue
        teile = z.split()
        was = teile[0]
        if was == "warte":
            time.sleep(float(teile[1]))
        elif was == "warteauf":
            ok = warte_auf(serial, teile[1], int(teile[2]), float(teile[3]))
            print("plan: warteauf %s >=%s -> %s" % (teile[1], teile[2], "ok" if ok else "TIMEOUT"))
        elif was == "marke":
            print("plan: %s" % " ".join(teile[1:]))
        elif was == "klick":
            x, y = (int(v) for v in teile[1].split(","))
            m.klick(x, y)
            print("plan: klick %d,%d" % (x, y))
        elif was in ("ziel", "rziel"):
            p, fehler = ziel_holen(serial, teile[1:])
            if p is None:
                print("plan: ZIEL NICHT GEFUNDEN: %s -- %s"
                      % (" ".join(teile[1:]), fehler))
            else:
                x, y = (int(v) for v in p.split(","))
                if was == "rziel":
                    m.rklick(x, y)
                else:
                    m.klick(x, y)
                print("plan: %s %s -> %d,%d" % (was, " ".join(teile[1:]), x, y))
        elif was == "rklick":
            x, y = (int(v) for v in teile[1].split(","))
            m.rklick(x, y)
            print("plan: rklick %d,%d" % (x, y))
        elif was == "tippe":
            m.tippe(teile[1])
            print("plan: tippe %s" % teile[1])
        elif was == "taste":
            m.cmd("sendkey %s" % teile[1], 0.2)
            time.sleep(0.5)
            print("plan: taste %s" % teile[1])
        elif was == "foto":
            n = m.foto(os.path.join(out, teile[1] + ".ppm"))
            print("plan: foto %s (%d Oktette)" % (teile[1], n))
        else:
            print("plan: unbekannter Schritt '%s'" % was)
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
