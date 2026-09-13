#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/hotplug/monitor.py -- EIN STICK, IM BETRIEB GESTECKT UND GEZOGEN.

    monitor.py <monitor-socket> <serielle-datei> <drehbuch>

Der Unterschied zu `tools/wm/monitor.py` (Maus und Tasten) und
`tools/k11/keys.py` (Text) ist genau eine Sache: hier wird die HARDWARE
veraendert, waehrend die Maschine laeuft. QEMU kann das ueber den
Monitor, und zwar mit denselben zwei Befehlen, mit denen ein Mensch
einen Stick in ein Brett steckt und wieder herauszieht:

    device_add usb-storage,id=<name>,drive=<laufwerk>
    device_del <name>

DAS IST DER GANZE PUNKT DIESER RUNDE. Ein Stick, der beim Start schon
steckt, misst das Aufzaehlen -- mehr nicht. Erst ein Stick, der
WAEHREND DES BETRIEBS kommt, misst den Weg, um den es geht: der
Zeitgeber sieht den Anschlusswechsel, die Schreibtischschleife nimmt
das Geraet auf, die Naht haengt es ein, die Seitenleiste zeigt es.

DIE BEFEHLE DES DREHBUCHS (eine Zeile, ein Befehl):

    stecke <id> <datei>   einen Stick anstecken (drive + device_add)
    ziehe <id>            abziehen -- OHNE Auswerfen, die Gegenprobe
    warte <sekunden>      anhalten
    aufzeile <text>       warten, bis <text> auf der seriellen Leitung
                          steht (hoechstens 60 s). DAS ist die
                          Synchronisierung, mit der dieser Laeufer ohne
                          feste Schlafzeiten auskommt -- eine feste
                          Zahl waere auf einer belasteten Maschine
                          entweder zu kurz (rot ohne Fehler) oder zu
                          lang (die Abnahme dauert Stunden).
    foto <datei.ppm>      ein Bildschirmfoto
    taste <name>          eine Taste (sendkey)
    text <zeichen>        ein Text, Zeichen fuer Zeichen
    maus <dx> <dy>        die Maus bewegen
    klick                 linke Taste, druecken und loslassen
    monitor <roh>         irgendein Monitorbefehl, roh

Zeilen mit `#` sind Anmerkungen.
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
    def __init__(self, pfad):
        self.s = None
        bis = time.time() + 20.0
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
            raise SystemExit("kein Monitor an %s" % pfad)
        time.sleep(0.3)
        self.leeren()

    def leeren(self):
        self.s.settimeout(0.4)
        try:
            while True:
                if not self.s.recv(65536):
                    break
        except OSError:
            pass

    def tu(self, befehl):
        self.s.sendall((befehl + "\n").encode())
        time.sleep(0.12)
        self.leeren()


def tasten_fuer(zeichen):
    if zeichen in EINFACH:
        return [EINFACH[zeichen]]
    if zeichen in SHIFT:
        return ["shift-" + SHIFT[zeichen]]
    if zeichen.isdigit() or (zeichen.isalpha() and zeichen.islower()):
        return [zeichen]
    if zeichen.isalpha() and zeichen.isupper():
        return ["shift-" + zeichen.lower()]
    return []


def warte_auf(datei, muster, grenze=60.0):
    """Bis <muster> in der seriellen Datei steht. Rueckgabe: hat es geklappt."""
    bis = time.time() + grenze
    muster_b = muster.encode()
    while time.time() < bis:
        try:
            with open(datei, "rb") as f:
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
        zeilen = f.read().splitlines()
    for roh in zeilen:
        z = roh.strip()
        if not z or z.startswith("#"):
            continue
        teile = z.split()
        cmd = teile[0]
        if cmd == "stecke":
            ident, datei = teile[1], teile[2]
            # ERST das Laufwerk, DANN das Geraet. Andersherum haengt ein
            # usb-storage ohne Ruecken in der Maschine.
            m.tu("drive_add 0 id=%s,if=none,file=%s,format=raw" % (ident, datei))
            m.tu("device_add usb-storage,id=dev%s,drive=%s" % (ident, ident))
            print("   stecke %s (%s)" % (ident, datei))
        elif cmd == "ziehe":
            ident = teile[1]
            m.tu("device_del dev%s" % ident)
            print("   ziehe %s" % ident)
        elif cmd == "warte":
            time.sleep(float(teile[1]))
        elif cmd == "aufzeile":
            muster = z.split(None, 1)[1]
            if warte_auf(seriell, muster):
                print("   gesehen: %s" % muster)
                n_ok += 1
            else:
                print("   NICHT GESEHEN (60 s): %s" % muster)
                n_bad += 1
        elif cmd == "foto":
            ziel = teile[1]
            m.tu("screendump %s" % ziel)
            # `screendump` ist fertig, wenn die Datei nicht mehr waechst.
            bis = time.time() + 20.0
            letzte = -1
            while time.time() < bis:
                try:
                    jetzt = os.path.getsize(ziel)
                except OSError:
                    jetzt = -1
                if jetzt > 0 and jetzt == letzte:
                    break
                letzte = jetzt
                time.sleep(0.25)
            print("   foto %s (%s Oktette)"
                  % (ziel, os.path.getsize(ziel) if os.path.exists(ziel) else "keine"))
        elif cmd == "taste":
            m.tu("sendkey %s" % teile[1])
        elif cmd == "text":
            for c in z.split(None, 1)[1]:
                for t in tasten_fuer(c):
                    m.tu("sendkey %s" % t)
        elif cmd == "maus":
            m.tu("mouse_move %s %s" % (teile[1], teile[2]))
        elif cmd == "klick":
            m.tu("mouse_button 1")
            time.sleep(0.15)
            m.tu("mouse_button 0")
        elif cmd == "monitor":
            m.tu(z.split(None, 1)[1])
        else:
            print("   unbekannter Befehl: %s" % z)
            n_bad += 1
    print("monitor: %d erwartete Zeilen gesehen, %d nicht" % (n_ok, n_bad))
    return 1 if n_bad else 0


if __name__ == "__main__":
    sys.exit(main())
