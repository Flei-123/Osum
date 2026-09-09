#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/design/fahren.py -- EIN START, VIELE BILDER.

    fahren.py <monitor-socket> <serial.txt> <ausgabeverzeichnis> <drehbuch>

Die Runden davor haben je Bild eine eigene Maschine gestartet: bauen,
booten, EIN Foto, beenden.  Fuer eine Bestandsaufnahme von sieben
Ansichten sind das sieben Starts a rund vierzig Sekunden, und sieben
Maschinen sind sieben verschiedene Uhrzeiten in der Leiste -- ein
Vorher/Nachher-Vergleich, bei dem sich nebenbei die Uhr bewegt, ist ein
Vergleich mit Rauschen darin.

Also: EIN Start, EINE Verbindung zum QEMU-Monitor, und ein Drehbuch,
das dazwischen klickt, tippt und fotografiert.

Befehle im Drehbuch (eine Zeile je Befehl, `#` ist eine Anmerkung):

    warte <sekunden>            anhalten
    warteauf <regex> [|| frist] warten, bis der regex in serial.txt steht
    fahre <x>,<y>               den Zeiger dorthin, ohne zu klicken
    klick <x>,<y>               dorthin fahren und einmal klicken
    doppel <x>,<y>              dorthin fahren und zweimal klicken
    klickauf <name>             das zuletzt gemeldete Rechteck <name>
                                anklicken (siehe unten)
    doppelauf <name>            dasselbe, zweimal
    taste <name>                sendkey
    foto <name>                 screendump nach <ausgabe>/<name>.ppm

DIE RECHTECKE.  Die Programme dieses Systems melden ihre Widgets auf
der seriellen Leitung -- `launcher: rect id=2 kind=5 x=12 y=82 w=416
h=166`, `settings: rect name=wtb x=.. y=.. w=.. h=..`, `taskbar: start
x=4 y=3 w=30 h=22`.  Ein Klick, der aus einer solchen Zeile gerechnet
ist, trifft das, was das PROGRAMM gemeldet hat, und nicht das, was
jemand aus einem alten Bild abgelesen hat.  Genau daran ist die Runde
THEMESTORE mit `click=680,51` haengengeblieben: die Zahl stimmt genau
so lange, bis sich das Fenster verschiebt.

Umgerechnet wird mit dem Ursprung des Fensters: `<programm>: geom x= y=`
plus Rahmen (2) und Titelleiste (22) -- dieselben zwei Zahlen, die
`wlib.say_painted` benutzt.  Wer ein Rechteck ohne Fensterbezug meldet
(die Taskleiste), gibt schon Bildschirmkoordinaten an.

Namen fuer `klickauf`:

    start           der Startknopf         (taskbar: start x= y= w= h=)
    glocke          die Meldungen          (taskbar: field noti ...)
    tbbtn<N>        Fensterknopf N         (taskbar: btn i=N ...)
    netz            die Symbolgruppe       (taskbar: field net ...)
    uhr             die Uhr                (taskbar: field clock ...)
    lrect<N>        Widget N des Starters  (launcher: rect id=N ...)
    lzeile<N>       Zeile N der Trefferliste des Starters
    srect<NAME>     Widget NAME der Einstellungen (settings: rect name=)
    frect<N>        Widget N des Dateimanagers (explorer: rect id=N)
"""
import os
import re
import socket
import sys
import time

BORDER = 2
TITLE_H = 22


def lies(pfad):
    try:
        with open(pfad, "rb") as f:
            return f.read().decode("latin1")
    except OSError:
        return ""


class Fahrer:
    def __init__(self, sock, serial, out):
        self.serial = serial
        self.out = out
        self.s = None
        bis = time.time() + 20.0
        while time.time() < bis:
            try:
                s = socket.socket(socket.AF_UNIX)
                s.settimeout(5.0)
                s.connect(sock)
                self.s = s
                break
            except OSError:
                time.sleep(0.1)
        if self.s is None:
            raise SystemExit("kein Monitor an %s" % sock)
        time.sleep(0.3)
        self.leeren()
        self.x, self.y = 0, 0
        self.ecke()

    def leeren(self):
        try:
            self.s.settimeout(0.4)
            while True:
                if not self.s.recv(65536):
                    break
        except OSError:
            pass
        finally:
            self.s.settimeout(5.0)

    def cmd(self, zeile):
        self.s.sendall((zeile + "\n").encode())
        time.sleep(0.06)
        self.leeren()

    # --- der Zeiger.  `mouse_move` ist RELATIV (PS/2 kennt nichts
    # anderes), und ein Paket traegt neun Bit je Achse.  Also: erst in
    # die linke obere Ecke, wo der Anschlag die Vorgeschichte loescht,
    # dann in Schritten unter 128 heraus.  Dieselbe Route wie
    # tools/themestore/click.py, nur dass die Verbindung stehen bleibt.
    def ecke(self):
        for _ in range(8):
            self.cmd("mouse_move -120 -120")
        self.x, self.y = 0, 0

    def fahre(self, x, y):
        self.ecke()
        dx, dy = x, y
        while dx > 0 or dy > 0:
            sx, sy = min(dx, 120), min(dy, 120)
            self.cmd("mouse_move %d %d" % (sx, sy))
            dx -= sx
            dy -= sy
        self.x, self.y = x, y

    def klick(self, x, y, mal=1, taste=1):
        self.fahre(x, y)
        time.sleep(0.35)
        for i in range(mal):
            self.cmd("mouse_button %d" % taste)
            # RUNDE EXPLORER-2, GEMESSEN: DER DOPPELKLICK WAR ZU LANGSAM.
            #
            # `wlib.on_down` nimmt zwei Klicks als Doppelklick, wenn
            # zwischen ihnen WENIGER ALS 100 TICKS liegen -- der Ticker
            # laeuft mit 100 Hz, das ist also eine Sekunde. Der Abstand
            # hier war 0.05 + 0.12 + 0.05 = 0.22 s, und trotzdem hat der
            # Gast 109 Ticks gemessen (`wlib: klick r=0 dop=0 dt=109`):
            # jedes `self.cmd` schickt ueber den Monitor und WARTET auf
            # die Antwort, und unter TCG kostet dieser Umlauf ein
            # Vielfaches der Schlafzeit. Der Doppelklick fiel damit
            # knapp aus dem Fenster, und ein Doppelklick auf einen
            # Ordner tat nichts -- was wie ein Fehler des Programms
            # aussah und keiner war.
            #
            # Also: zwischen den zwei Klicks eines Doppelklicks wird
            # NICHT geschlafen. Die Umlaufzeit des Monitors ist schon
            # mehr Abstand, als ein Mensch je erzeugt.
            if mal == 1:
                time.sleep(0.05)
            self.cmd("mouse_button 0")
        time.sleep(1.2)

    def taste(self, name):
        self.cmd("sendkey %s" % name)
        time.sleep(0.4)

    def warteauf(self, muster, frist=25.0):
        r = re.compile(muster)
        bis = time.time() + frist
        while time.time() < bis:
            if r.search(lies(self.serial)):
                return True
            time.sleep(0.2)
        return False

    # --- das Foto.  `screendump` kehrt zurueck, BEVOR die Datei fertig
    # ist; gewartet wird, bis die Groesse steht.  (tools/gfx/screenshot.py
    # hat das herausgefunden, hier steht es noch einmal, weil diese
    # Verbindung nicht neu aufgebaut wird.)
    def foto(self, name, frist=30.0):
        ziel = os.path.join(self.out, name + ".ppm")
        if os.path.exists(ziel):
            os.unlink(ziel)
        self.cmd("screendump %s" % ziel)
        letzte, ruhig = -1, 0
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
                    print("foto %s %d Oktette" % (name, jetzt))
                    return True
            else:
                ruhig, letzte = 0, jetzt
        print("foto %s FEHLGESCHLAGEN" % name)
        return False

    # ------------------------------------------------ die Rechtecke
    def fenster(self, prog):
        """Der Ursprung der Malflaeche eines Programmfensters."""
        t = lies(self.serial)
        m = None
        for m in re.finditer(
                r"%s: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % prog, t):
            pass
        if m is None:
            return None
        return (int(m.group(1)) + BORDER, int(m.group(2)) + TITLE_H)

    def rechteck(self, name):
        t = lies(self.serial)

        def letzte(muster):
            m = None
            for m in re.finditer(muster, t):
                pass
            return m

        # DIE LEISTE MELDET IN IHREN EIGENEN KOORDINATEN.  `taskbar:
        # start x=4 y=3` ist die Ecke IM Fenster der Leiste, und das
        # Fenster steht bei `taskbar: geom x=0 y=772`.  Der erste
        # Versuch dieser Runde hat die beiden verwechselt und auf
        # (19,14) geklickt -- oben links auf den Schreibtisch.  Genau
        # deshalb steht hier eine Umrechnung und keine Zahl.
        gm = letzte(r"taskbar: geom edge=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
        tb = (int(gm.group(1)), int(gm.group(2))) if gm else (0, 0)
        if name == "start":
            m = letzte(r"taskbar: start x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            if m is None:
                return None
            return (tb[0] + int(m.group(1)), tb[1] + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        # RUNDE SYSTEMBUS: die Glocke und die FENSTERKNOEPFE der Leiste.
        # Ohne den Fensterknopf gibt es keinen Weg, ein Fenster
        # anzuklicken, das der Schreibtisch selbst gestartet hat -- und
        # ohne den keinen Weg, im Terminal etwas zu tippen.
        if name == "glocke":
            m = letzte(r"taskbar: field noti x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            if m is None:
                return None
            return (tb[0] + int(m.group(1)), tb[1] + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name.startswith("tbbtn"):
            n = int(name[5:])
            m = letzte(r"taskbar: btn i=%d id=\d+ x=(\d+) y=(\d+) "
                       r"w=(\d+) h=(\d+)" % n)
            if m is None:
                return None
            return (tb[0] + int(m.group(1)), tb[1] + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name in ("netz", "uhr"):
            f = "net" if name == "netz" else "clock"
            m = letzte(r"taskbar: field %s x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % f)
            if m is None:
                return None
            return (tb[0] + int(m.group(1)), tb[1] + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name.startswith("fmbar"):
            # Eintrag <N> der Menueleiste des Dateimanagers.  Die
            # Leiste meldet ihr Rechteck (`explorer: rect id=0 kind=8`);
            # die Eintraege darin sind gleich breit gesetzt und der
            # erste faengt am linken Innenrand an.
            n = int(name[5:])
            m = letzte(r"explorer: rect id=0 kind=8 "
                       r"x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            o = self.fenster("explorer")
            if m is None or o is None:
                return None
            return (o[0] + int(m.group(1)) + 8 + n * 60,
                    o[1] + int(m.group(2)), 44, int(m.group(4)))
        if name.startswith("emenue"):
            # Die Zeile <N> des offenen Kontextmenues des Dateimanagers.
            # Es meldet Ecke und Hoehe des MENUEFENSTERS
            # (`explorer: menurect wx= wy= wh=`); die Zeilenhoehe ist
            # die des Systems (`launcher: rows ... zh=`), sonst 20.
            n = int(name[6:])
            m = letzte(r"explorer: menurect wx=(\d+) wy=(\d+) wh=(\d+)")
            if m is None:
                return None
            z = letzte(r"rows x=\d+ base=\d+ zh=(\d+)")
            zh = int(z.group(1)) if z else 20
            return (int(m.group(1)) + 8, int(m.group(2)) + 4 + n * zh, 90, zh)
        if name == "qsalle":
            # Die unterste Zeile des Kontrollzentrums ("Alle
            # Einstellungen").  Das Feld meldet nur seine eigene Ecke
            # (`qs: open x= y= w= h=`); die Zeile darin steht als
            # Konstante in kernel/user/qs.fi -- PAD=10, FH=22, und sie
            # sitzt unten, also H - PAD - FH.
            m = letzte(r"qs: open x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            if m is None:
                return None
            x, y = int(m.group(1)), int(m.group(2))
            w, h = int(m.group(3)), int(m.group(4))
            return (x + 10, y + h - 10 - 22, w - 20, 22)
        if name.startswith("lrect"):
            n = int(name[5:])
            m = letzte(r"launcher: rect id=%d kind=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % n)
            o = self.fenster("launcher")
            if m is None or o is None:
                return None
            return (o[0] + int(m.group(1)), o[1] + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name.startswith("lzeile"):
            n = int(name[6:])
            m = letzte(r"launcher: rect id=2 kind=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            z = letzte(r"launcher: rows x=\d+ base=\d+ zh=(\d+)")
            o = self.fenster("launcher")
            if m is None or z is None or o is None:
                return None
            zh = int(z.group(1))
            return (o[0] + int(m.group(1)), o[1] + int(m.group(2)) + n * zh,
                    int(m.group(3)), zh)
        if name.startswith("srect"):
            k = name[5:]
            m = letzte(r"settings: rect name=%s x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % k)
            o = self.fenster("settings")
            if m is None or o is None:
                return None
            return (o[0] + int(m.group(1)), o[1] + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name.startswith("ftabzeile"):
            # RUNDE EXPLORER-2: EINE BESTIMMTE ZEILE DER DATEITABELLE.
            # Ohne sie kann ein Drehbuch nur die MITTE der Tabelle
            # treffen (`klickauf ftab`), und welche Zeile da liegt,
            # haengt daran, wie viele Dateien der Ordner hat -- ein
            # Test, der "geh in den ersten Ordner" sagen will, koennte
            # es nicht sagen.
            #
            # Gerechnet aus dem, was das Programm SELBST meldet: `kopf=`
            # ist die Grundlinie der Kopfzeile und `zh=` die
            # Zeilenhoehe (`explorer: rows ... zh= kopf=`). Die erste
            # Datenzeile faengt eine Kopfhoehe unter dem Tabellenrand an
            # -- dieselbe Rechnung wie `wlib.row_under`, nur andersherum.
            n = int(name[9:])
            m = letzte(r"explorer: rect id=\d+ kind=6 "
                       r"x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            z = letzte(r"explorer: rows x=\d+ base=\d+ zh=(\d+)")
            o = self.fenster("explorer")
            if m is None or z is None or o is None:
                return None
            zh = int(z.group(1))
            # Die Kopfzeile ist zh + 4 hoch (wlib.paint_table `kopf`),
            # danach beginnt Zeile 0.
            y0 = int(m.group(2)) + zh + 5 + n * zh
            return (o[0] + int(m.group(1)), o[1] + y0, int(m.group(3)), zh)
        if name in ("ftab", "fbaum"):
            # RUNDE EXPLORER-2: DIE TABELLE UND DIE SEITENLEISTE, OHNE
            # IHRE NUMMER ZU KENNEN. `frect<N>` verlangt die Widgetzahl,
            # und die verschiebt sich mit jedem Bedienelement, das
            # dazukommt (die Brosamenleiste sind allein zwoelf). Die ART
            # verschiebt sich nicht: kind=6 ist die Tabelle, kind=5 eine
            # Liste (`wlib.K_TABLE` / `K_LIST`).
            art = 6 if name == "ftab" else 5
            m = letzte(r"explorer: rect id=\d+ kind=%d "
                       r"x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % art)
            o = self.fenster("explorer")
            if m is None or o is None:
                return None
            return (o[0] + int(m.group(1)), o[1] + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name.startswith("frect"):
            n = int(name[5:])
            m = letzte(r"explorer: rect id=%d kind=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % n)
            o = self.fenster("explorer")
            if m is None or o is None:
                return None
            return (o[0] + int(m.group(1)), o[1] + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        return None


def main():
    if len(sys.argv) < 5:
        print(__doc__)
        return 2
    sock, serial, out, buch = sys.argv[1:5]
    os.makedirs(out, exist_ok=True)
    f = Fahrer(sock, serial, out)
    fehler = 0
    for roh in open(buch, encoding="utf-8"):
        z = roh.strip()
        if not z or z.startswith("#"):
            continue
        teile = z.split(None, 1)
        b = teile[0]
        arg = teile[1].strip() if len(teile) > 1 else ""
        if b == "warte":
            time.sleep(float(arg))
        elif b == "warteauf":
            st = arg.split("||")
            # Die Anfuehrungszeichen gehoeren der Lesbarkeit des
            # Drehbuchs und nicht dem regulaeren Ausdruck.  Der erste
            # Lauf dieser Runde hat nach `'launcher: ready'` MIT
            # Hochkommas gesucht, nie etwas gefunden und trotzdem
            # weitergeklickt -- und das Ergebnis war ein zweites
            # Startmenue statt eines Dateimanagers.
            muster = st[0].strip().strip("'\"")
            ok = f.warteauf(muster, float(st[1]) if len(st) > 1 else 25.0)
            print("warteauf %s -> %s" % (muster, "da" if ok else "NICHT DA"))
            if not ok:
                fehler += 1
        # RUNDE EXPLORER-2, GEMESSEN: DIE RECHTE TASTE IST 2 UND NICHT 4.
        # `mouse_button` des QEMU-Monitors legt links auf Bit 0, RECHTS
        # auf Bit 1 und die Mitte auf Bit 2 -- dieselbe Reihenfolge, die
        # `kernel/ps2m.fi` liefert und die `wlib.on_down` mit `btn & 2`
        # prueft. Hier stand 4, also die MITTLERE Taste: jedes `rklick`
        # dieses Laeufers ging als Mittelklick durch, kein Kontextmenue
        # klappte auf, und das Bild 31-kontextmenue.png zeigte deshalb
        # keines -- ein Fehler des Laeufers, nicht des Programms.
        elif b in ("klick", "doppel", "fahre", "rklick"):
            x, y = (int(v) for v in arg.split(","))
            if b == "fahre":
                f.fahre(x, y)
            elif b == "rklick":
                f.klick(x, y, 1, taste=2)
            else:
                f.klick(x, y, 2 if b == "doppel" else 1)
        elif b in ("klickauf", "doppelauf", "rklickauf"):
            r = f.rechteck(arg)
            if r is None:
                print("klickauf %s -> KEIN RECHTECK GEMELDET" % arg)
                fehler += 1
                continue
            x, y = r[0] + r[2] // 2, r[1] + r[3] // 2
            print("klickauf %s -> %d,%d  (rect %d,%d %dx%d)"
                  % (arg, x, y, r[0], r[1], r[2], r[3]))
            if b == "rklickauf":
                f.klick(x, y, 1, taste=2)
            else:
                f.klick(x, y, 2 if b == "doppelauf" else 1)
        elif b == "taste":
            f.taste(arg)
        elif b == "foto":
            if not f.foto(arg):
                fehler += 1
        else:
            print("unbekannter Befehl: %s" % z)
            fehler += 1
    print("drehbuch fertig, fehler=%d" % fehler)
    return 0


if __name__ == "__main__":
    sys.exit(main())
