#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/blech2/maus.py -- EIN SYNTHETISCHER BEWEGUNGSSTROM UEBER QMP.

    maus.py <qmp-socket> <sekunden> <hz> [schluessel=wert ...]

        breite=3424 hoehe=1440   die Flaeche, auf der der Zeiger laeuft
        klick_ms=2000            alle so viele Millisekunden ein Linksklick
        klickfeld=x0,y0,x1,y1    NUR dort wird geklickt (Schreibtischflaeche,
                                 nicht Terminal, nicht Leiste, nicht Kreuz)
        tasten=<n>               danach n Tastendruecke (a..z) in 50-ms-Abstand
        shot=<ziel.ppm>          am Ende ein Bildschirmfoto ueber QMP
        heim=1                   vorher in die linke obere Ecke fahren

WARUM QMP UND NICHT DER HMP-MONITOR. `tools/wm/monitor.py` schickt
`mouse_move` als Textbefehl und wartet nach jedem eine Zehntelsekunde --
zehn Bewegungen je Sekunde. Justins Maus meldet 125 bis 1000 Berichte
je Sekunde. Der Fensterring (`wm.EV_SLOTS`) faellt erst um, wenn MEHR
hineinkommt, als der Abholer zwischen zwei Runden holt -- also braucht
die Abnahme einen Strom in DIESER Groessenordnung. QMP nimmt
`input-send-event` als JSON ohne Wartezeit an; ein Ereignis je
Millisekunde ist damit erreichbar (die WIRKLICH erreichte Rate wird
gemessen und mitgeteilt, nicht behauptet).

WAS QEMU DARAUS MACHT, UND WARUM DAS EHRLICH DAZUGESAGT WIRD. Das
USB-Mausgeraet von QEMU (hw/input/hid.c) fasst Bewegungen, die zwischen
zwei Abfragen des Wirts eintreffen, zu EINEM Bericht zusammen und traegt
den Rest, der nicht in acht Bit passt, in den naechsten. Mit einem
Meldeintervall von 8-10 ms kommen im Gast also rund 100-125 Berichte je
Sekunde an -- die Rate einer gewoehnlichen USB-Maus. Der Weg Bericht ->
`ps2m.usb_packet` -> `wm.on_mouse` -> `ev_push` wird damit mit ECHTEN
xHCI-Berichten belastet, nicht mit einem Kernelhaken. Fuer die 1000-Hz-
Last im Kern gibt es zusaetzlich das Bootwort `mausflut=<hz>` (kgui.fi).

DER ZEIGERORT IST EINE RECHNUNG. Nach dem Heimfahren (grosse negative
Schritte, der Anschlag bei 0,0 loescht die Vorgeschichte) ist jeder
weitere Schritt klein (|d| <= 4 je Millisekunde, also hoechstens rund 40
je Bericht -- weit unter den 127, die ein Bericht traegt), und der Weg
bleibt mit Rand im Bild. Damit ist die Stelle, an der geklickt wird,
bekannt und nicht gehofft: `klickfeld` haelt die Klicks vom Terminal,
der Leiste und dem Schliesskreuz fern.
"""
import json
import math
import os
import socket
import sys
import time


def verbinden(pfad, frist=30.0):
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


class Qmp:
    def __init__(self, s):
        self.s = s
        self.f = s.makefile("rb")
        self.gruss = json.loads(self.f.readline())
        self.befehl("qmp_capabilities")

    def befehl(self, name, **args):
        d = {"execute": name}
        if args:
            d["arguments"] = args
        self.s.sendall((json.dumps(d) + "\n").encode())
        while True:
            zeile = self.f.readline()
            if not zeile:
                raise RuntimeError("QMP: Verbindung weg")
            antwort = json.loads(zeile)
            if "event" in antwort:
                continue
            return antwort

    def rel(self, dx, dy):
        ev = []
        if dx:
            ev.append({"type": "rel", "data": {"axis": "x", "value": int(dx)}})
        if dy:
            ev.append({"type": "rel", "data": {"axis": "y", "value": int(dy)}})
        if not ev:
            return
        self.befehl("input-send-event", events=ev)

    def taste(self, down, name):
        self.befehl("input-send-event", events=[
            {"type": "btn", "data": {"down": down, "button": name}}])

    def key(self, down, qcode):
        self.befehl("input-send-event", events=[
            {"type": "key", "data": {"down": down,
                                     "key": {"type": "qcode", "data": qcode}}}])

    def screendump(self, ziel):
        if os.path.exists(ziel):
            os.unlink(ziel)
        a = self.befehl("screendump", filename=ziel)
        # warten, bis die Datei steht und sich nicht mehr aendert
        alt = -1
        gleich = 0
        bis = time.time() + 20
        while time.time() < bis:
            if os.path.exists(ziel):
                n = os.path.getsize(ziel)
                if n == alt and n > 0:
                    gleich += 1
                    if gleich >= 3:
                        return True
                else:
                    gleich = 0
                alt = n
            time.sleep(0.1)
        return "error" not in a


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    sock = sys.argv[1]
    sekunden = float(sys.argv[2])
    hz = float(sys.argv[3])
    opt = {"breite": "3424", "hoehe": "1440", "klick_ms": "2000",
           "klickfeld": "", "tasten": "0", "shot": "", "heim": "1"}
    for a in sys.argv[4:]:
        k, _, v = a.partition("=")
        opt[k] = v
    W = int(opt["breite"])
    H = int(opt["hoehe"])
    klick_ms = int(opt["klick_ms"])
    feld = None
    if opt["klickfeld"]:
        feld = tuple(int(x) for x in opt["klickfeld"].split(","))

    s = verbinden(sock)
    if s is None:
        print("maus: kein QMP an %s" % sock)
        return 1
    q = Qmp(s)

    px, py = W // 2, H // 2
    if opt["heim"] == "1":
        # Heim: 80 Schritte a -120 in beiden Achsen, mit 10 ms Abstand,
        # damit jeder Schritt in einen eigenen Bericht faellt. Danach
        # steht der Zeiger am Anschlag (0,0), egal wo er vorher war.
        for _ in range(80):
            q.rel(-120, -120)
            time.sleep(0.010)
        time.sleep(0.3)
        px, py = 0, 0

    # DER WEG: eine Lissajous-Figur ueber die ganze Flaeche, mit Rand.
    ax = W / 2 - 40
    ay = H / 2 - 40
    cx = W / 2
    cy = H / 2
    Tx = 7.0
    Ty = 17.0
    n_soll = int(sekunden * hz)
    dt = 1.0 / hz
    gesendet = 0
    klicks = 0
    klick_unten = False
    klick_seit = 0.0
    naechster_klick = klick_ms / 1000.0
    t0 = time.perf_counter()
    for i in range(n_soll):
        t = i * dt
        # auf den Takt warten
        soll = t0 + t
        jetzt = time.perf_counter()
        if soll > jetzt:
            time.sleep(soll - jetzt)
        tx = cx + ax * math.sin(2 * math.pi * t / Tx)
        ty = cy + ay * math.sin(2 * math.pi * t / Ty)
        dx = int(round(tx - px))
        dy = int(round(ty - py))
        dx = max(-4, min(4, dx))
        dy = max(-4, min(4, dy))
        if dx or dy:
            q.rel(dx, dy)
            px += dx
            py += dy
            gesendet += 1
        # Klick: nieder, und 40 ms spaeter wieder hoch
        if klick_unten and t - klick_seit >= 0.040:
            q.taste(False, "left")
            klick_unten = False
        if not klick_unten and t >= naechster_klick:
            drin = True
            if feld is not None:
                drin = feld[0] <= px < feld[2] and feld[1] <= py < feld[3]
            if drin:
                q.taste(True, "left")
                klick_unten = True
                klick_seit = t
                klicks += 1
                naechster_klick = t + klick_ms / 1000.0
    if klick_unten:
        time.sleep(0.05)
        q.taste(False, "left")
    dauer = time.perf_counter() - t0
    rate = gesendet / dauer if dauer > 0 else 0

    tasten = int(opt["tasten"])
    for k in range(tasten):
        qc = chr(ord("a") + (k % 26))
        q.key(True, qc)
        time.sleep(0.025)
        q.key(False, qc)
        time.sleep(0.025)

    time.sleep(1.0)
    shot_ok = None
    if opt["shot"]:
        shot_ok = q.screendump(opt["shot"])
    print("maus: bewegungen=%d dauer_s=%.1f rate_hz=%.0f klicks=%d tasten=%d "
          "zeiger=%d,%d shot=%s" % (gesendet, dauer, rate, klicks, tasten,
                                    px, py, shot_ok))
    return 0


if __name__ == "__main__":
    sys.exit(main())
