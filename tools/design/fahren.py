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

    # ==================================== RUNDE ECHTHARDWARE-5
    # `nahe=True` -- OHNE DEN UMWEG UEBER DIE ECKE.
    #
    # `fahre` faehrt IMMER erst nach 0,0 und von dort zum Ziel; anders
    # laesst sich mit relativen PS/2-Bewegungen nicht absolut zielen.
    # Fuer das Kontrollzentrum ist dieser Umweg toedlich: es pollt den
    # Zeiger und schliesst, sobald eine Taste AUSSERHALB heruntergeht
    # -- und schon der Weg durch die Ecke reicht, damit es sich fuer
    # ueberfluessig haelt (`qs: closed by outside`, gemessen in genau
    # diesem Lauf).
    #
    # Mit `nahe` wird vom ZULETZT bekannten Punkt aus relativ gefahren.
    # Das setzt voraus, dass die Buchfuehrung stimmt -- sie tut es,
    # solange nur diese Klasse den Zeiger bewegt.
    def klick_nahe(self, x, y, mal=1, taste=1):
        dx, dy = x - self.x, y - self.y
        while dx or dy:
            sx = max(-120, min(120, dx))
            sy = max(-120, min(120, dy))
            self.cmd("mouse_move %d %d" % (sx, sy))
            dx -= sx
            dy -= sy
        self.x, self.y = x, y
        time.sleep(0.35)
        for _ in range(mal):
            self.cmd("mouse_button %d" % taste)
            time.sleep(0.05)
            self.cmd("mouse_button 0")
        time.sleep(1.2)

    # RUNDE ECHTHARDWARE-5: ziehen vom zuletzt bekannten Punkt aus,
    # ohne den Umweg ueber 0,0. Begruendung siehe `klick_nahe`.
    def ziehe_nahe(self, x0, y0, x1, y1, schritte=8):
        dx, dy = x0 - self.x, y0 - self.y
        while dx or dy:
            sx = max(-120, min(120, dx))
            sy = max(-120, min(120, dy))
            self.cmd("mouse_move %d %d" % (sx, sy))
            dx -= sx
            dy -= sy
        self.x, self.y = x0, y0
        time.sleep(0.35)
        self.cmd("mouse_button 1")
        time.sleep(0.25)
        cx, cy = x0, y0
        for k in range(1, schritte + 1):
            zx = x0 + (x1 - x0) * k // schritte
            zy = y0 + (y1 - y0) * k // schritte
            ddx, ddy = zx - cx, zy - cy
            while ddx or ddy:
                sx = max(-120, min(120, ddx))
                sy = max(-120, min(120, ddy))
                self.cmd("mouse_move %d %d" % (sx, sy))
                ddx -= sx
                ddy -= sy
            cx, cy = zx, zy
            time.sleep(0.15)
        self.x, self.y = cx, cy
        time.sleep(0.35)
        self.cmd("mouse_button 0")
        time.sleep(1.2)

    # ============================================== RUNDE ANHEFTEN
    # ZIEHEN MIT EINEM FOTO MITTENDRIN. Ohne das gibt es kein Bild vom
    # ZUSTAND WAEHREND des Zugs -- und genau das ist der Beleg dafuer,
    # dass die Luecke mitwandert. Vorher und nachher zu fotografieren
    # beweist nur das Ergebnis, nicht die Bewegung.
    def ziehe_mit_foto(self, x0, y0, x1, y1, name, schritte=8):
        self.fahre(x0, y0)
        time.sleep(0.35)
        self.cmd("mouse_button 1")
        time.sleep(0.25)
        cx, cy = x0, y0
        halt = schritte // 2
        for k in range(1, schritte + 1):
            zx = x0 + (x1 - x0) * k // schritte
            zy = y0 + (y1 - y0) * k // schritte
            ddx, ddy = zx - cx, zy - cy
            while ddx or ddy:
                sx = max(-120, min(120, ddx))
                sy = max(-120, min(120, ddy))
                self.cmd("mouse_move %d %d" % (sx, sy))
                ddx -= sx
                ddy -= sy
            cx, cy = zx, zy
            time.sleep(0.15)
            if k == halt and name:
                # Die Taste bleibt gedrueckt: das Bild zeigt den Zug.
                time.sleep(0.6)
                self.foto(name)
        self.x, self.y = cx, cy
        time.sleep(0.35)
        self.cmd("mouse_button 0")
        time.sleep(1.2)

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

    # RUNDE ECHTHARDWARE-5: die Geometrie EINES Fensters, so wie der
    # Server sie zuletzt gemeldet hat. Rahmen und Titelhoehe stehen
    # nicht in der Zeile -- sie sind BORDER/TITLE_H mal der
    # Vervielfachung, und die liest sich aus der Leistenhoehe ab
    # (`taskbar: geom ... h=`): 40 heisst 1, 80 heisst 2.
    def fenstergeom(self, wid):
        t = lies(self.serial)
        m = None
        for m in re.finditer(
                r"wm: fen i=\d+ id=%d x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % wid,
                t):
            pass
        if m is None:
            return None
        x, y, w, h = (int(m.group(i)) for i in (1, 2, 3, 4))
        # 64-Bit-Zweierkomplement: der Server meldet negative Werte
        # als sehr grosse Zahlen.
        if x > (1 << 63):
            x -= (1 << 64)
        if y > (1 << 63):
            y -= (1 << 64)
        sk = 1
        g = None
        for g in re.finditer(r"taskbar: geom edge=\d+ x=\d+ y=\d+ w=\d+ h=(\d+)", t):
            pass
        if g is not None and int(g.group(1)) >= 60:
            sk = 2
        return (x, y, w, h, 2 * sk, 22 * sk)

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
        # ==================================== RUNDE ECHTHARDWARE-5
        # `qstm` und `qsset` -- die zwei Knopfzeilen des
        # Kontrollzentrums, so wie es sie SELBST meldet:
        #     qs: zeile tm y=987 h=32
        # Grund siehe qs.fi: `qs: text ... y=321` ist die Grundlinie
        # der Schrift und nicht das Feld; wer darauf klickt, trifft
        # daneben.
        if name in ("qstm", "qsset"):
            wort = "tm" if name == "qstm" else "set"
            m = letzte(r"qs: zeile %s y=(\d+) h=(\d+)" % wort)
            g = letzte(r"qs: geo x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            if m is None or g is None:
                return None
            y0, hh = int(m.group(1)), int(m.group(2))
            return (int(g.group(1)) + 8, y0, int(g.group(3)) - 16, hh)
        if name == "hellspur":
            m = letzte(r"qs: hell spur von=(\d+) bis=(\d+) ym=(\d+)")
            if m is None:
                return None
            x0, x1, ym = (int(m.group(i)) for i in (1, 2, 3))
            return (x0, ym - 4, x1 - x0, 8)
        gm = letzte(r"taskbar: geom edge=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
        tb = (int(gm.group(1)), int(gm.group(2))) if gm else (0, 0)
        # ============================================ RUNDE ANHEFTEN
        # `pin0`..`pin5` -- die ANGEHEFTETEN Knoepfe, so wie die Leiste
        # sie selbst meldet:
        #     taskbar: pin certus x=96 y=8 w=64 h=64 sym=1 laeuft=0
        # Der Name im Drehbuch ist die STELLE und nicht das Programm,
        # weil die Stelle genau das ist, was diese Runde veraendert.
        if name.startswith("pin") and name[3:].isdigit():
            k = int(name[3:])
            alle = list(re.finditer(
                r"taskbar: pin (\w+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", t))
            if not alle:
                return None
            # NUR DER LETZTE ANSTRICH ZAEHLT. Die Leiste meldet diese
            # Zeilen bei JEDEM Anstrich neu; davor stehen dieselben
            # Namen mit den Koordinaten von vorher, und nach einem
            # Ziehen sind das die FALSCHEN. Wie viele Anhefter es gibt,
            # sagt der Abstand zwischen zwei Vorkommen desselben
            # Namens -- gezaehlt wird vom Ende her.
            letzter = alle[-1].group(1)
            n = 1
            for m2 in reversed(alle[:-1]):
                if m2.group(1) == letzter:
                    break
                n += 1
            letzten = alle[-n:]
            if k >= len(letzten):
                return None
            m = letzten[k]
            return (tb[0] + int(m.group(2)), tb[1] + int(m.group(3)),
                    int(m.group(4)), int(m.group(5)))
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
        # ==================================== RUNDE ECHTHARDWARE-5
        # `ziehkante <id> <kante> <dx>,<dy>` -- an einer KANTE des
        # Fensters <id> ziehen, die Stelle aus der zuletzt gemeldeten
        # Geometrie gerechnet.
        #
        # WARUM NICHT MIT ZAHLEN AUS DEM DREHBUCH. Justins Befund D
        # betrifft alle vier Kanten und alle vier Ecken; die Greifzone
        # ist `GRIP0 * uiscale` = 8 bzw. 16 Bildpunkte breit. Wer sie
        # mit getippten Zahlen sucht, trifft nach dem ERSTEN Ziehen
        # daneben, weil das Fenster dann woanders steht -- genau das ist
        # mir in dieser Runde zweimal passiert und hat zwei Laeufe
        # gekostet. Hier wird die Stelle JEDES MAL neu aus
        # `wm: fen ... x= y= w= h=` gerechnet.
        #
        # Kanten: l r o u  und die Ecken lo ro lu ru.
        elif b == "ziehkante":
            t = arg.split()
            wid = int(t[0])
            kante = t[1]
            dx, dy = (int(v) for v in t[2].split(","))
            g = f.fenstergeom(wid)
            if g is None:
                print("ziehkante %d -> KEINE GEOMETRIE gemeldet" % wid)
                fehler += 1
                continue
            wx, wy, ww, wh, bo, ti = g
            # Die Arbeitsflaeche liegt bei (wx+bo, wy+ti); die
            # Greifzone ist der Rand darum. In die MITTE der Zone.
            lx = wx + bo - 2
            rx = wx + bo + ww + 1
            oy = wy + 2
            uy = wy + ti + wh + 1
            mx = wx + bo + ww // 2
            my = wy + ti + wh // 2
            stelle = {"l": (lx, my), "r": (rx, my), "o": (mx, oy),
                      "u": (mx, uy), "lo": (lx, oy), "ro": (rx, oy),
                      "lu": (lx, uy), "ru": (rx, uy)}
            if kante not in stelle:
                print("ziehkante: unbekannte Kante %s" % kante)
                fehler += 1
                continue
            x0, y0 = stelle[kante]
            f.ziehe(x0, y0, x0 + dx, y0 + dy)
            print("ziehkante id=%d %s von %d,%d um %d,%d "
                  "(fenster %d,%d %dx%d bo=%d ti=%d)"
                  % (wid, kante, x0, y0, dx, dy, wx, wy, ww, wh, bo, ti))
        # RUNDE ECHTHARDWARE-5: klicken OHNE den Weg ueber die Ecke.
        # Fuer alles, was sich bei einem Druck daneben schliesst --
        # also fuer das Kontrollzentrum.
        elif b == "klicknah":
            if "," in arg:
                x, y = (int(v) for v in arg.split(","))
            else:
                r = f.rechteck(arg)
                if r is None:
                    print("klicknah %s -> KEIN RECHTECK GEMELDET" % arg)
                    fehler += 1
                    continue
                x, y = r[0] + r[2] // 2, r[1] + r[3] // 2
            f.klick_nahe(x, y)
            print("klicknah %s -> %d,%d" % (arg, x, y))
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
        # RUNDE ECHTHARDWARE-5: ziehen OHNE den Weg ueber die Ecke --
        # dasselbe wie `klicknah`, nur mit gedrueckter Taste. Fuer die
        # zwei Regler im Kontrollzentrum, das sich sonst unterwegs
        # schliesst.
        # ============================================ RUNDE ANHEFTEN
        # `ziehfoto <rechteck> <dx> <bildname>` -- das Rechteck an
        # seiner MITTE greifen, um dx BILDPUNKTE waagerecht ziehen und
        # mittendrin fotografieren. In Punkten, nicht in Prozent: eine
        # Verschiebung um "zwei Plaetze" ist eine Strecke und kein
        # Anteil der Knopfbreite.
        elif b == "ziehfoto":
            t = arg.split()
            r = f.rechteck(t[0])
            if r is None:
                print("ziehfoto %s -> KEIN RECHTECK GEMELDET" % t[0])
                fehler += 1
                continue
            dx = int(t[1])
            x0 = r[0] + r[2] // 2
            y0 = r[1] + r[3] // 2
            f.ziehe_mit_foto(x0, y0, x0 + dx, y0, t[2] if len(t) > 2 else None)
            print("ziehfoto %s -> %d,%d nach %d,%d  (rect %d,%d %dx%d)"
                  % (t[0], x0, y0, x0 + dx, y0, r[0], r[1], r[2], r[3]))
        elif b == "ziehspurnah":
            t = arg.split()
            r = f.rechteck(t[0])
            if r is None:
                print("ziehspurnah %s -> KEIN RECHTECK GEMELDET" % t[0])
                fehler += 1
                continue
            p0, p1 = (int(v) for v in t[1].split(","))
            y = r[1] + r[3] // 2
            x0 = r[0] + r[2] * p0 // 100
            x1 = r[0] + r[2] * p1 // 100
            f.ziehe_nahe(x0, y, x1, y)
            print("ziehspurnah %s -> %d,%d nach %d,%d" % (t[0], x0, y, x1, y))
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
            # RUNDE ECHTHARDWARE-5: der Doppelpunkt und die uebrigen
            # Zeichen einer URL. Ohne sie fiel aus
            # `https://example.com/` still `https//example.com/` --
            # `fetch` hat das voellig zu Recht abgelehnt, und es sah
            # aus wie ein Netzfehler.
            namen = {" ": "spc", "-": "minus", ".": "dot",
                     ",": "comma", "/": "slash", "_": "shift-minus",
                     # US-Belegung (`lang=en`, so faehrt der Stick):
                     # der Doppelpunkt liegt auf Umschalt+Semikolon.
                     ":": "shift-semicolon", ";": "semicolon",
                     "=": "equal", "?": "shift-slash",
                     "&": "shift-7", "%": "shift-5"}
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
