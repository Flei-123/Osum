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
                self.relative_maus()
                return True
            except OSError:
                time.sleep(0.2)
        raise RuntimeError("kein Monitor an %s" % self.sockpfad)

    def relative_maus(self):
        """AUF DAS RELATIVE ZEIGEGERAET UMSCHALTEN -- der Fund dieser Runde.

        `-device usb-tablet` haengt ZWEI Zeigegeraete an die Maschine,
        und der Monitor bedient von sich aus das TABLET:

              Mouse #2: QEMU PS/2 Mouse
            * Mouse #3: QEMU HID Tablet (absolute)

        Ein Tablet ist ABSOLUT. Diese Datei rechnet aber RELATIV (siehe
        `ecke`): sie faehrt in die linke obere Ecke, verlaesst sich auf
        den Anschlag und zaehlt von dort. Fuer ein absolutes Geraet ist
        `mouse_move dx dy` kein Schritt, sondern ein Ort -- und damit
        stimmt ab dem zweiten Sprung nichts mehr.

        GEMESSEN, derselbe Zug auf derselben Maschine
        (pruef/mausquelle.py):

            tablet (absolut)  kl 0 -> 0   Fenster (24,40) -> (24,40)
            ps2    (relativ)  kl 0 -> 0   Fenster (24,40) -> (204,170)

        Der Zug ueber die PS/2-Maus verschiebt das Fenster um genau die
        180/130 Bildpunkte, die er verschieben soll. Genau das ist der
        Grund, warum Runde DURCHKLICK und der erste Durchgang dieser
        Runde bei 4.1/4.2 "GEHT NICHT" gemessen haben: nicht der
        Fensterserver, sondern der Monitor hat die Bewegung verschluckt.
        Einzelne Klicks wirkten trotzdem -- ein Klick braucht keine
        Wegstrecke, nur einen Ort, und den setzt das Tablet selbst.

        ABER: DER SCHALTER GILT NUR FUERS ZIEHEN, und das ist gemessen.
        Der KERN sieht in diesem Aufbau ausschliesslich die USB-Maus --

            usb: port=5 ... class=03:00:00 driver=mouse

        -- eine PS/2-Maus taucht in seinem Mitschnitt nirgends auf.
        Schaltet man den Monitor dauerhaft auf `mouse_set 2`, gehen die
        Ereignisse an ein Geraet, das der Kern nicht abfragt: gemessen
        blieb der Zeiger dann ueber den ganzen Lauf auf `xy=639,399`
        stehen, `kl=0`, und kein einziger `taskbar: click` kam an.

        Beim ZIEHEN ist es umgekehrt: dort wirkt nur die PS/2-Maus
        (siehe `ziehe`). Also wird pro Vorgang umgeschaltet und danach
        zurueck -- der Zustand steht in `self.relativ`.
        """
        self.relativ = False

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

    def _maus(self, nummer):
        """Das Zeigegeraet des Monitors umschalten (1 = Tablet, 2 = PS/2)."""
        try:
            self.s.sendall(("mouse_set %d\n" % nummer).encode())
            time.sleep(0.35)
            self._leeren()
            return True
        except OSError:
            return False

    def ziehe(self, x1, y1, x2, y2):
        """Druecken, fahren, loslassen -- fuer Fenster verschieben.

        RUNDE TUERSCHLOSS, ZWEI FEHLER DARIN BEHOBEN:

        1. DIE TASTE MUSS WIRKLICH LOSGEHEN. Blieb sie haengen, stand
           danach der ganze Schreibtisch: der Zeiger klebte bei
           (566,437), die Leiste hoerte bei `paints=68` auf zu malen und
           kein Tastendruck kam mehr an. Von aussen sah das aus wie ein
           Absturz -- es war eine gedrueckte Maustaste. Das Loslassen
           steht jetzt in einem `finally` und wird zweimal geschickt;
           ein zweites `mouse_button 0` schadet nicht.

        2. DER REST DER STRECKE GING VERLOREN. `dx // schritte` mal
           `schritte` ist nicht `dx` -- bei 260 Bildpunkten in 5
           Schritten fehlten 4. Fuer einen Griff, der 12 Bildpunkte
           breit ist, entscheidet das. Jetzt wird die Strecke
           aufgeteilt und der Rest im letzten Schritt mitgenommen.
        """
        # ZUM ZIEHEN AUF DIE RELATIVE MAUS. Begruendung siehe
        # `relative_maus`: mit dem Tablet zaehlt der Kern beim Ziehen
        # nicht eine Taste (kl 0 -> 0), mit der PS/2-Maus verschiebt
        # sich das Fenster um genau die verlangte Strecke.
        self._maus(2)
        self.gehe(x1, y1)
        self.sag("mouse_button 1", 0.2)
        try:
            dx, dy = x2 - x1, y2 - y1
            schritte = max(1, max(abs(dx), abs(dy)) // 40 + 1)
            gx = gy = 0
            for i in range(schritte):
                # bis hierher soll gefahren sein -- die Differenz zum
                # schon Gefahrenen ist der Schritt. So bleibt kein Rest.
                zx = dx * (i + 1) // schritte
                zy = dy * (i + 1) // schritte
                self.sag("mouse_move %d %d" % (zx - gx, zy - gy), 0.06)
                gx, gy = zx, zy
        finally:
            self.sag("mouse_button 0", 0.2)
            self.sag("mouse_button 0", 0.1)
            # ... und zurueck auf das Tablet, mit dem die KLICKS wirken.
            self._maus(1)
        self.x, self.y = x2, y2
        time.sleep(0.5)

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
              "Ü": "shift-bracket_left",
              # RUNDE ALLTAG -- DIE ZEICHEN, DIE AUF DEUTSCH WOANDERS
              # LIEGEN. `ZEICHEN` oben nennt die US-POSITION der Taste,
              # und der Kern legt sie DEUTSCH aus (kernel/kbd.fi). Fuer
              # Buchstaben ist das gleich, fuer Satzzeichen nicht:
              # `sendkey slash` gab ein MINUS, und aus `ls /data` wurde
              # `ls -data` -- das listete die Wurzel und sah wie eine
              # Antwort aus. GEMESSEN am 19.09. im Lauf `ziehen2`; im
              # selben Lauf gab `sendkey minus` ein `ß`, was die
              # deutsche Belegung beweist.
              # `<` und `>` liegen auf DEUTSCH auf einer eigenen Taste
              # links neben dem Y (QEMU nennt sie `less`); auf US-Lage
              # gibt es sie nur als Umschalt-Komma/-Punkt. GEMESSEN:
              # ohne diese zwei Zeilen fiel das `>` einer Umlenkung
              # ERSATZLOS weg -- aus `echo eins > /data/t1.txt` wurde
              # `echo eins  /data/t1.txt`, die Shell schrieb beides auf
              # den Schirm, `echo` meldete rc=0, und die Datei entstand
              # NIE. Von aussen sah das wie ein kaputtes Dateisystem aus.
              # DIE TASTE NEBEN DER LINKEN UMSCHALTTASTE, Scancode
              # 0x56. QEMU kennt fuer sie KEINEN der ueblichen Namen
              # (`less` schickt nichts, was hier ankommt -- gemessen:
              # das Zeichen fiel als LEERZEICHEN an). Ueber die ROHE
              # Scancode-Nummer geht es: `sendkey 0x56`. Der Kern legt
              # sie deutsch aus (kernel/drv/hid/kbd.fi:1051 und :1129):
              # ohne Umschalt `<`, mit Umschalt `>`.
              # Z UND Y SIND VERTAUSCHT, und das ist keine Feinheit.
              # `sendkey` nennt die US-POSITION der Taste, der Kern legt
              # sie DEUTSCH aus -- also gibt `sendkey z` ein `y` und
              # `sendkey y` ein `z`. GEMESSEN am 21.09.2026 im Lauf
              # `korb3`: aus `papierkorb zurueck 1` wurde auf dem Schirm
              # `papierkorb yurueck 1`, das Programm kannte den Befehl
              # nicht (rc=2) und schrieb seine Nutzungszeile -- und die
              # Abnahme meldete daraufhin "nach 'zurueck' kam der Inhalt
              # der Datei nicht", also einen Fehler des SYSTEMS, wo ein
              # Fehler des PRUEFSTANDS vorlag. Dieselbe Sorte Fund wie
              # `>` und `/` in den Zeilen darueber.
              "z": "y", "y": "z", "Z": "shift-y", "Y": "shift-z",
              "<": "0x56", ">": "shift-0x56",
              "/": "shift-7", "-": "slash", "ß": "minus",
              "?": "shift-minus", "_": "shift-slash",
              ";": "shift-comma", ":": "shift-dot",
              "=": "shift-0", "+": "bracket_right", "*": "shift-bracket_right",
              "(": "shift-8", ")": "shift-9", "&": "shift-6",
              "%": "shift-5", "$": "shift-4", "!": "shift-1",
              '"': "shift-2"}
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
