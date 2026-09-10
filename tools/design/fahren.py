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
    # ================================================== RUNDE MERGE-10
    # ACHT SCHRITTE REICHEN NUR BIS 960 BILDPUNKTE.
    #
    # Hier standen acht Bewegungen um -120, also -960 in jede Richtung.
    # Der Zeiger wird an der Bildschirmkante angehalten, deshalb ist
    # "weit genug nach links oben" dasselbe wie "in der Ecke" -- aber
    # eben nur, solange der Schirm nicht groesser ist als 960.
    #
    # Auf 1280x800 geht das auf (-960 < -800). Auf 2560x1440 NICHT:
    # der Zeiger bleibt 1440-960 = 480 Bildpunkte ueber dem oberen Rand
    # stehen, und JEDE Fahrt danach ist um genau diesen Betrag
    # verschoben.
    #
    # GEMESSEN (Abnahme dieser Runde, 2560x1440):
    #   taskbar: click x=40 y=36  hits=start   <- der erste Klick sitzt
    #   taskbar: click x=40 y=71  hits=none    <- alle weiteren nicht
    # Der zweite Klick auf Start kam nie an, das Startmenue blieb zu,
    # und die Klicks auf seine Zeilen gingen ins Leere -- der
    # Dateimanager startete nicht, und `03-explorer` zeigte den
    # Schreibtisch. Das sah aus wie ein Fehler der Oberflaeche bei
    # hoher Aufloesung und war einer des Fahrers.
    #
    # Genug ist: mehr Schritte, als der groesste denkbare Schirm hoch
    # ist. 32 x 120 = 3840 traegt 4K in beiden Richtungen; die
    # Bewegungen kosten je einen Monitorumlauf und laufen nur einmal je
    # Klick.
    ECKSCHRITTE = 32

    def ecke(self):
        for _ in range(self.ECKSCHRITTE):
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

    # ============================================ RUNDE ECHTHARDWARE-3
    # ZIEHEN: DRUECKEN, IN SCHRITTEN FAHREN, LOSLASSEN.
    #
    # Zwei Befunde dieser Runde lassen sich mit `klick` gar nicht
    # pruefen, weil sie eine BEWEGUNG BEI GEDRUECKTER TASTE verlangen:
    # die Fenstergroesse (`wm.fi` `S_SIZING`) und der Helligkeitsregler
    # (`qs.fi`, seit dieser Runde `EV_MOVE`). Ein Sprung von A nach B
    # waere kein Ziehen -- der Server sieht dann EINE Bewegung, und
    # genau die hat vorher auch schon funktioniert. Also in Schritten,
    # damit wirklich mehrere `EV_MOVE` entstehen.
    def ziehe(self, x0, y0, x1, y1, schritte=8):
        # ======================================== RUNDE ECHTHARDWARE-3
        # WAEHREND DES ZIEHENS DARF DER ZEIGER NICHT UEBER DIE ECKE.
        #
        # `fahre` faehrt IMMER erst nach 0,0 (`ecke`) und von dort zum
        # Ziel -- absolut positionieren geht ueber `mouse_move` nur so.
        # Beim ZIEHEN ist das toedlich: die gedrueckte Taste wandert
        # mit, das Kontrollzentrum sieht einen Druck bei 0,0 und
        # schliesst sich voellig zu Recht (`qs: closed by outside`).
        # Es sah aus, als taete der Regler nichts -- der Fehler lag im
        # LAEUFER, und er hat mich drei Laeufe gekostet.
        #
        # Also: zum Startpunkt absolut fahren, druecken, und ab da nur
        # noch RELATIV bewegen.
        self.fahre(x0, y0)
        time.sleep(0.35)
        self.cmd("mouse_button 1")
        time.sleep(0.25)
        cx, cy = x0, y0
        for k in range(1, schritte + 1):
            zx = x0 + (x1 - x0) * k // schritte
            zy = y0 + (y1 - y0) * k // schritte
            dx, dy = zx - cx, zy - cy
            while dx or dy:
                sx = max(-120, min(120, dx))
                sy = max(-120, min(120, dy))
                self.cmd("mouse_move %d %d" % (sx, sy))
                dx -= sx
                dy -= sy
            cx, cy = zx, zy
            time.sleep(0.15)
        self.x, self.y = cx, cy
        time.sleep(0.35)
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
        # ==================================== RUNDE ECHTHARDWARE-3
        # `hellspur` -- die Rinne des Helligkeitsreglers, so wie das
        # Kontrollzentrum sie SELBST meldet:
        #     qs: hell spur von=898 bis=1266 ym=592
        # Damit muss niemand mehr PAD/GAP/TOP2/ZH nachrechnen. Ich habe
        # genau das in dieser Runde zweimal getan und zweimal
        # danebengegriffen -- beide Male lag der Griff ausserhalb des
        # Panels, das sich daraufhin voellig zu Recht schloss.
        if name == "hellspur":
            m = letzte(r"qs: hell spur von=(\d+) bis=(\d+) ym=(\d+)")
            if m is None:
                return None
            x0, x1, ym = (int(m.group(i)) for i in (1, 2, 3))
            return (x0, ym - 4, x1 - x0, 8)
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
        # RUNDE ECHTHARDWARE-3: `ziehe <x0>,<y0> <x1>,<y1>` und
        # `zieheauf <name> <dx>,<dy>` -- die Bewegung bei gedrueckter
        # Taste, ohne die sich weder die Fenstergroesse noch ein
        # Schieberegler pruefen laesst.
        elif b == "ziehe":
            t = arg.split()
            x0, y0 = (int(v) for v in t[0].split(","))
            x1, y1 = (int(v) for v in t[1].split(","))
            f.ziehe(x0, y0, x1, y1)
            print("ziehe %d,%d -> %d,%d" % (x0, y0, x1, y1))
        elif b == "zieheauf":
            t = arg.split()
            r = f.rechteck(t[0])
            if r is None:
                print("zieheauf %s -> KEIN RECHTECK GEMELDET" % t[0])
                fehler += 1
                continue
            dx, dy = (int(v) for v in t[1].split(","))
            # DIE UNTERE RECHTE ECKE des gemeldeten Rechtecks, zwei
            # Punkte hinein -- das ist der Griff.
            x0, y0 = r[0] + r[2] - 2, r[1] + r[3] - 2
            f.ziehe(x0, y0, x0 + dx, y0 + dy)
            print("zieheauf %s -> von %d,%d um %d,%d  (rect %d,%d %dx%d)"
                  % (t[0], x0, y0, dx, dy, r[0], r[1], r[2], r[3]))
        # RUNDE ECHTHARDWARE-3: `ziehespur <name> <von%>,<bis%>` --
        # entlang eines gemeldeten Rechtecks ziehen, in Prozent seiner
        # Breite. Fuer Schieberegler: die Zahlen bleiben richtig, auch
        # wenn sich das Panel verschiebt oder die Aufloesung wechselt.
        elif b == "ziehespur":
            t = arg.split()
            r = f.rechteck(t[0])
            if r is None:
                print("ziehespur %s -> KEIN RECHTECK GEMELDET" % t[0])
                fehler += 1
                continue
            p0, p1 = (int(v) for v in t[1].split(","))
            y = r[1] + r[3] // 2
            x0 = r[0] + r[2] * p0 // 100
            x1 = r[0] + r[2] * p1 // 100
            f.ziehe(x0, y, x1, y)
            print("ziehespur %s -> %d,%d nach %d,%d  (rect %d,%d %dx%d)"
                  % (t[0], x0, y, x1, y, r[0], r[1], r[2], r[3]))
        elif b == "taste":
            f.taste(arg)
        # RUNDE ECHTHARDWARE-4: `tippe <wort>` -- ein Wort Zeichen fuer
        # Zeichen. Zum Pruefen des Suchfeldes im Startmenue braucht es
        # das: `taste t`, `taste e`, `taste r`, `taste m` untereinander
        # zu schreiben ist dieselbe Sache, nur unleserlich, und bei
        # einem Tippfehler im Drehbuch faellt es niemandem auf.
        elif b == "tippe":
            namen = {" ": "spc", "-": "minus", ".": "dot",
                     ",": "comma", "/": "slash", "_": "shift-minus"}
            for ch in arg:
                f.taste(namen.get(ch, ch))
                time.sleep(0.12)
            print("tippe %s (%d Zeichen)" % (arg, len(arg)))
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
