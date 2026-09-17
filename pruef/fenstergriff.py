#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""fenstergriff.py -- 4.1 VERSCHIEBEN und 4.2 GROESSE, gegen ZWEI Abbilder.

    python3 fenstergriff.py <name> <osum.mb> <root.img> [breite] [hoehe]

WORUM ES GEHT. BEFUND-DURCHKLICK-2 sagt fuer 4.1 "VORHER GEHT, NACHHER
GEHT NICHT" und laesst offen, ob das eine Regression dieser Runde ist
oder ein Messfehler. "Nicht abschliessend geklaert" ist keine Antwort.
Also: DIESELBE Ziehbewegung, DIESELBEN Koordinaten, gegen das alte
Abbild (merge8) und das neue -- und die Fensterlage kommt aus der
seriellen Leitung des Fensterservers, nicht aus einem Bild.

WIE HIER GEZOGEN WIRD, und warum die Koordinaten aus der Meldung kommen.
Der Fensterserver rechnet in `on_mouse` (kernel/ui/wm.fi):

    lokal_x = x - win_x - inx        inx = border      (2 * uisc)
    lokal_y = y - win_y - iny        iny = title_h     (22 * uisc)

    lokal_y < 0                              -> Titelleiste, ZIEHEN
    lokal_x >= W_W - grip && lokal_y >= W_H - grip  -> GRIFF, GROESSE

`W_W`/`W_H` sind die INNENmasse (das, was `wm: fen ... w= h=` meldet);
aussen ist das Fenster `w + 2*border` breit und `h + title_h + border`
hoch. Der Griff ist `12 * uisc` gross. Daraus folgt bildpunktgenau:

    Titelleiste:  y zwischen win_y + 4 und win_y + title_h - 1
                  x NICHT im Schliessfeld (rechts oben) und nicht in
                  den drei Schaltflaechen -> also linke Haelfte nehmen
    Griff:        x = win_x + border + W_W - grip/2
                  y = win_y + title_h + W_H - grip/2

DIE TASTE MUSS BEIM DRUECKEN SCHON AM ZIEL SEIN. Der ganze Hit-Test
oben steht in `if btn != alt` -- er laeuft also NUR bei einem WECHSEL
des Tastenzustands, und der Ort, der dabei zaehlt, ist der, an dem die
Taste heruntergeht. Ein Drueck-dann-Fahr ist richtig; ein Fahr-mit-
gedrueckter-Taste-ueber-den-Griff waere es nicht.
"""
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
from klick import Maschine

NAME = sys.argv[1] if len(sys.argv) > 1 else "fg"
MB = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HIER, "osum.mb")
IMG = sys.argv[3] if len(sys.argv) > 3 else os.path.join(HIER, "root.img")
BREITE = int(sys.argv[4]) if len(sys.argv) > 4 else 1280
HOEHE = int(sys.argv[5]) if len(sys.argv) > 5 else 800
D = os.path.join(HIER, "laeufe", NAME)
SER = os.path.join(D, "serial.txt")

# Die Masse des Schmucks aus kernel/wm.fi (uisc == 1 bei diesen
# Aufloesungen -- `wm: fen ... tp=15` bestaetigt die Schriftgroesse).
BORDER = 2
TITLE_H = 22
GRIP = 12


def s():
    try:
        return open(SER, "rb").read().replace(b"\x00", b"").decode(
            "utf-8", "replace")
    except OSError:
        return ""


def start():
    """DER WEG UEBER start.sh, und nicht ein eigener QEMU-Aufruf.

    Der erste Entwurf dieser Datei baute die Kommandozeile selbst
    zusammen -- und bekam keine einzige `wm: fen`-Zeile, obwohl der
    Schreibtisch stand. Der Unterschied zu start.sh ist nicht die
    Kommandozeile (die ist Wort fuer Wort dieselbe), sondern das
    Zeitlimit und die Umgebung drumherum. Zwei Wege, dieselbe Maschine
    zu starten, sind einer zu viel: hier wird derselbe genommen, den
    auch durchklick3.py nimmt, und die Abbilder werden vorher an die
    Stelle gelegt, von der er liest.
    """
    os.makedirs(D, exist_ok=True)
    # Kern und Wurzel an den Ort, von dem start.sh liest.
    if os.path.abspath(MB) != os.path.join(HIER, "osum.mb"):
        subprocess.run(["cp", "-f", MB, os.path.join(HIER, "osum.mb")],
                       check=True)
    if os.path.abspath(IMG) != os.path.join(HIER, "root.img"):
        subprocess.run(["cp", "-f", IMG, os.path.join(HIER, "root.img")],
                       check=True)
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(BREITE), str(HOEHE)], check=True,
                   capture_output=True, text=True, timeout=60)
    t0 = time.time()
    while time.time() - t0 < 180:
        if "taskbar: start x=" in s():
            # AUF DIE FENSTERLISTE WARTEN, nicht auf eine Frist.
            # `wm.wins_say` haengt am PULS (kgui), und der kommt nicht
            # im Sekundentakt. Vier Sekunden reichten nicht: der
            # Schreibtisch stand, `taskbar:`-Zeilen liefen, und
            # `wm: fen` kam trotzdem erst spaeter. Wer hier zu frueh
            # weitermacht, misst "kein Fenster" und meint das System.
            bis = time.time() + 120
            while time.time() < bis:
                if fenster(s()):
                    time.sleep(2)
                    return True, time.time() - t0
                time.sleep(0.5)
            return True, time.time() - t0
        time.sleep(0.3)
    return None, None


def fenster(t):
    """Alle gemeldeten Fensterlagen: id -> (x, y, w, h, lay, fl)."""
    aus = {}
    for m in re.finditer(r"wm: fen i=\d+ id=(\d+) x=(\d+) y=(\d+) w=(\d+) "
                         r"h=(\d+) lay=(\d+) fl=(\d+)", t):
        aus[int(m.group(1))] = tuple(int(m.group(k)) for k in range(2, 8))
    return aus


def warte_neue_lage(wid, frist=60):
    """Auf eine FRISCHE Fensterzeile warten.

    `wm: fen` haengt am Puls (kgui), und der kommt nicht im
    Sekundentakt -- in einem Lauf standen ganze drei Zeilen. Wer nach
    zwei Sekunden nachsieht, liest die Lage VOR dem Zug und meldet
    "nicht verschoben", obwohl das Fenster laengst woanders steht.
    Genau das ist beim ersten Anlauf dieser Messung passiert.
    """
    n = len(re.findall(r"wm: fen i=\d+ id=%d " % wid, s()))
    bis = time.time() + frist
    while time.time() < bis:
        if len(re.findall(r"wm: fen i=\d+ id=%d " % wid, s())) > n:
            time.sleep(0.5)
            return fenster(s()).get(wid)
        time.sleep(0.4)
    return fenster(s()).get(wid)


def ziel_fenster(t):
    """Das Fenster mit Schmuck: lay=1 (L_NORMAL) und fl ohne F_NODECO(2)."""
    best = None
    for wid, (x, y, w, h, lay, fl) in fenster(t).items():
        if lay == 1 and (fl & 2) == 0 and (fl & 1) == 0 and w >= 200:
            best = (wid, x, y, w, h)
    return best


def main():
    p, boot = start()
    if not p or boot is None:
        print("kein Schreibtisch -- Abbruch")
        return 1
    print("hochgefahren nach %.1f s  (%s)" % (boot, os.path.basename(IMG)),
          flush=True)
    time.sleep(3)
    m = Maschine(os.path.join(D, "mon.sock"), BREITE, HOEHE)

    z = ziel_fenster(s())
    if not z:
        print("kein Fenster mit Schmuck gemeldet")
        print("gemeldete Fenster:", fenster(s()))
        return 1
    wid, x, y, w, h = z
    print("Zielfenster id=%d  x=%d y=%d w=%d h=%d" % (wid, x, y, w, h),
          flush=True)

    # ---------------------------------------------------- 4.1 ZIEHEN
    # In die Titelleiste, LINKE Haelfte: dort liegt weder das
    # Schliessfeld noch eine der drei Schaltflaechen.
    tx = x + BORDER + 40
    ty = y + TITLE_H // 2
    print("\n4.1 ziehen: greife Titelleiste bei (%d,%d)" % (tx, ty),
          flush=True)
    vor = fenster(s()).get(wid)
    m.ziehe(tx, ty, tx + 200, ty + 150)
    nach = warte_neue_lage(wid)
    print("    vorher  %s" % (vor,))
    print("    nachher %s" % (nach,))
    bewegt = bool(vor and nach and (abs(nach[0] - vor[0]) > 20
                                    or abs(nach[1] - vor[1]) > 20))
    print("    -> VERSCHOBEN: %s" % ("JA" if bewegt else "NEIN"), flush=True)

    # ---------------------------------------------------- 4.2 GROESSE
    z2 = warte_neue_lage(wid)
    if z2:
        x2, y2, w2, h2 = z2[0], z2[1], z2[2], z2[3]
    else:
        x2, y2, w2, h2 = x, y, w, h
    # Der Griff liegt in den letzten GRIP Bildpunkten der INNENflaeche.
    # Mitte davon: W_W - GRIP/2 bzw. W_H - GRIP/2, plus der Versatz des
    # Schmucks (border links, title_h oben).
    gx = x2 + BORDER + w2 - GRIP // 2
    gy = y2 + TITLE_H + h2 - GRIP // 2
    print("\n4.2 groesse: greife Griff bei (%d,%d)" % (gx, gy), flush=True)
    print("    (Fenster x=%d y=%d w=%d h=%d; Griff ist %d gross)"
          % (x2, y2, w2, h2, GRIP))
    vor2 = fenster(s()).get(wid)
    m.ziehe(gx, gy, gx + 160, gy + 110)
    nach2 = warte_neue_lage(wid)
    print("    vorher  %s" % (vor2,))
    print("    nachher %s" % (nach2,))
    groesser = bool(vor2 and nach2 and (nach2[2] > vor2[2] + 20
                                        or nach2[3] > vor2[3] + 20))
    print("    -> GROESSER: %s" % ("JA" if groesser else "NEIN"), flush=True)

    # Was der Server ueber seine Zaehler sagt -- das trennt "Klick kam
    # nicht an" von "Klick kam an, Zweig nicht genommen".
    t = s()
    for marke in ("wm: hits", "S_DOWNS", "wm: downs"):
        for zeile in re.findall(r"%s[^\n]{0,50}" % marke, t)[-2:]:
            print("    |", zeile)
    m.sag("quit", 0.2)
    time.sleep(1)
    print("\nERGEBNIS %s: ziehen=%s groesse=%s"
          % (os.path.basename(IMG), "JA" if bewegt else "NEIN",
             "JA" if groesser else "NEIN"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
