#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""fenster.py -- Fensterverwaltung und Herunterfahren.

    python3 fenster.py <name> <breite> <hoehe>

  4.1 verschieben      Titelleiste ziehen
  4.2 Groesse ziehen   Griff unten rechts
  4.3 Alt+Tab          Fokuswechsel
  7.4 Herunterfahren   `shutdown` im Terminal -> QEMU MUSS weg sein

Alle Lagen kommen aus den Berichten des Fensterservers
(`wm: fen i=.. id=.. x=.. y=.. w=.. h=..`) und nicht aus dem Bild:
der Server ist die Stelle, die es weiss.
"""
import json
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
from klick import Maschine
import lesen

NAME = sys.argv[1] if len(sys.argv) > 1 else "f1"
BREITE = int(sys.argv[2]) if len(sys.argv) > 2 else 1280
HOEHE = int(sys.argv[3]) if len(sys.argv) > 3 else 800
D = os.path.join(HIER, "laeufe", NAME)
SHOTS = os.path.join(HIER, "shots", NAME)
os.makedirs(SHOTS, exist_ok=True)
SER = os.path.join(D, "serial.txt")
ERG = {}


def s():
    return lesen.text(SER)


def merke(nr, was, erg, beleg=""):
    ERG[nr] = {"was": was, "ergebnis": erg, "beleg": str(beleg)[:300]}
    print("%-5s %-40s %-12s %s" % (nr, was[:40], erg, str(beleg)[:70]))


def lage(fid, txt=None):
    """Die ZULETZT gemeldete Lage eines Fensters."""
    letzte = None
    for m in re.finditer(
            r"wm: fen i=\d+ id=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)",
            s() if txt is None else txt):
        if int(m.group(1)) == fid:
            letzte = tuple(int(m.group(k)) for k in (2, 3, 4, 5))
    return letzte


def lage_nach(fid, vorher, frist=20.0):
    """Auf die NAECHSTE Meldung warten, die sich von `vorher`
    unterscheidet.

    Der Fensterserver schreibt seine Liste nur ab und zu -- unmittelbar
    nach einem Zug steht dort noch die alte Lage. Wer sofort liest,
    misst "nichts passiert", obwohl das Fenster laengst woanders steht.
    GEMESSEN: nach dem Verschieben lag die neue Zeile
    (x=284 y=229) elf Berichte spaeter auf der Leitung, und der Laeufer
    hatte da schon "GEHT NICHT" geschrieben.
    """
    bis = time.time() + frist
    while time.time() < bis:
        jetzt = lage(fid)
        if jetzt and jetzt != vorher:
            return jetzt
        time.sleep(0.5)
    return lage(fid)


def warte_fenster(w, h, frist=60):
    bis = time.time() + frist
    while time.time() < bis:
        for i, lagen in lesen.fenster(s()).items():
            for x, y, bw, bh in lagen:
                if bw == w and bh == h:
                    return i, x, y, bw, bh
        time.sleep(1.0)
    return None


def main():
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(BREITE), str(HOEHE)], check=True,
                   capture_output=True, text=True, timeout=60)
    t0 = time.time()
    while time.time() - t0 < 120 and "taskbar: start x=" not in s():
        time.sleep(0.3)
    print("BOOT: %.1f s\n" % (time.time() - t0))
    time.sleep(2.5)
    m = Maschine(os.path.join(D, "mon.sock"), BREITE, HOEHE)

    t = warte_fenster(560, 380)
    if not t:
        merke("4.0", "Terminalfenster gefunden", "GEHT NICHT", "-")
        return schluss()
    fid, tx, ty, tw, th = t
    merke("4.0", "Terminalfenster gefunden", "GEHT",
          "id=%d (%d,%d) %dx%d" % (fid, tx, ty, tw, th))

    # ============================================== DIE RECHNUNG DAZU
    #
    # `wm: fen x= y=` ist die AEUSSERE Ecke des Fensters, `w= h=` die
    # INNERE Groesse -- das steht so in `wm.fi`: `paint_click` rechnet
    #
    #     lokal_x = x - win_x(i) - inx(i)      inx = BORDER0 = 2
    #     lokal_y = y - win_y(i) - iny(i)      iny = TITLE_H0 = 22
    #
    # und behandelt `lokal_y < 0` als Titelleiste. Daraus folgt:
    #   Titelleiste:  y + 2 .. y + 22
    #   Inhalt:       x + 2 .. x + 2 + w,  y + 22 .. y + 22 + h
    #   Griff:        die letzten GRIP0 = 12 Bildpunkte des Inhalts,
    #                 also um (x + 2 + w - 6, y + 22 + h - 6)
    #
    # Die erste Fassung dieses Laeufers zog an `y - 8` (ueber dem
    # Fenster, im Leeren) und an `y + h - 6` (mitten im Inhalt) -- und
    # mass daraufhin "verschieben geht nicht", obwohl Runde DURCHKLICK
    # es bildpunktgenau nachgewiesen hatte. Der Fehler lag im Laeufer.
    RAND = 2
    TITEL = 22
    GRIFF = 12

    # ------------------------------------------------ 4.1 verschieben
    vorher = lage(fid)
    m.ziehe(tx + tw // 2, ty + TITEL // 2, tx + tw // 2 + 260, ty + 200)
    nachher = lage_nach(fid, vorher)
    verschoben = bool(vorher and nachher and
                      (vorher[0] != nachher[0] or vorher[1] != nachher[1]))
    merke("4.1", "Fenster verschieben",
          "GEHT" if verschoben else "GEHT NICHT",
          "%s -> %s" % (vorher, nachher))
    m.foto(os.path.join(SHOTS, "01-verschoben.png"))

    # --------------------------------------------- 4.2 Groesse ziehen
    l = lage(fid) or (tx, ty, tw, th)
    x, y, w, h = l
    # Der Griff sitzt in der unteren rechten Ecke INNERHALB des Rahmens.
    # `wm.grip` ist GRIP0 * Skalierung; ein paar Bildpunkte hinein
    # treffen ihn sicher.
    m.ziehe(x + RAND + w - GRIFF // 2, y + TITEL + h - GRIFF // 2,
            x + RAND + w + 150, y + TITEL + h + 110)
    n = lage_nach(fid, l)
    groesser = bool(n and (n[2] > w or n[3] > h))
    merke("4.2", "Fenstergroesse ziehen",
          "GEHT" if groesser else "GEHT NICHT",
          "%dx%d -> %s" % (w, h, "%dx%d" % (n[2], n[3]) if n else "-"))
    m.foto(os.path.join(SHOTS, "02-groesse.png"))

    # ---------------------------------------------------- 4.3 Alt+Tab
    vf = re.findall(r"focus=(\d+)", s())
    m.taste("alt-tab")
    time.sleep(2.5)
    nf = re.findall(r"focus=(\d+)", s())
    merke("4.3", "Alt+Tab wechselt den Fokus",
          "GEHT" if vf and nf and vf[-1] != nf[-1] else "GEHT NICHT",
          "focus %s -> %s" % (vf[-1] if vf else "-", nf[-1] if nf else "-"))

    # ----------------------------------------------- 7.4 Herunterfahren
    try:
        pid = int(open(os.path.join(D, "pid")).read().strip())
    except Exception:
        pid = None
    if pid:
        l = lage(fid) or (tx, ty, tw, th)
        m.klick_auf(l[0] + RAND + l[2] // 2, l[1] + TITEL + l[3] // 2)
        time.sleep(1.0)
        m.tippe("shutdown")
        m.taste("ret")
        weg = False
        for _ in range(45):
            time.sleep(1.0)
            try:
                os.kill(pid, 0)
            except OSError:
                weg = True
                break
        merke("7.4", "Herunterfahren ueber die Oberflaeche",
              "GEHT" if weg else "GEHT NICHT",
              "QEMU %d %s" % (pid, "beendet" if weg else "laeuft noch"))

    merke("7.5", "keine Abstuerze",
          "GEHT" if lesen.abstuerze(s()) == 0 else "GEHT NICHT",
          "%d Treffer" % lesen.abstuerze(s()))
    return schluss()


def schluss():
    with open(os.path.join(D, "fenster.json"), "w") as f:
        json.dump(ERG, f, indent=1, ensure_ascii=False)
    print("\n-> %s/fenster.json" % D)
    return 0


if __name__ == "__main__":
    sys.exit(main())
