# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-zugbild.py -- RUNDE DESIGN-3: das Zugbild am Zeiger.
#
# GEMESSEN WIRD NICHT "sieht huebsch aus", sondern zwei Dinge, die
# nachpruefbar sind:
#   1. WAEHREND der Zug laeuft, meldet der Fensterserver EIN FENSTER
#      MEHR auf der Ebene L_TIP (6) als vorher -- das ist das Schild.
#   2. NACH dem Loslassen ist es wieder weg (kein haengendes Schild).
# Dazu Bilder mitten im Zug, damit ueberlappender Text auffaellt.
import re
import time

L_TIP = 6

lauf.sag("== DESIGN-3: Zugbild am Zeiger ==")


def fenster():
    alle = re.findall(
        r"wm: fen i=\d+ id=(\d+) x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+) lay=(\d+)",
        lauf.lies())
    d = {}
    for f in alle:
        d[int(f[0])] = tuple(int(v) for v in f[1:])
    return d


def tips():
    return sorted([i for i, v in fenster().items() if v[4] == L_TIP])


def startmenue_punkt(name):
    lauf.m.taste("meta_l")
    time.sleep(3)
    men = [(i, v) for i, v in fenster().items() if v[4] == 4]
    if not men:
        lauf.sag("  KEIN STARTMENUE")
        return False
    mid, (mx, my, mw, mh, _) = men[-1]
    lauf.m.klick_auf(mx + 207, my + 60)
    time.sleep(1)
    for _ in range(24):
        lauf.m.taste("backspace")
    time.sleep(1)
    lauf.m.tippe(name)
    time.sleep(2)
    lauf.m.taste("ret")
    time.sleep(5)
    return True


# ------------------------------------------------ 1. Dateimanager
lauf.sag("-- 1. Dateimanager starten --")
vor = set(fenster().keys())
startmenue_punkt("Datei")
lauf.bild("01-explorer")
neu = [i for i in fenster().keys() if i not in vor]
lauf.sag("  neue Fenster: %s" % sorted(neu))
if not neu:
    lauf.sag("ABBRUCH: kein Dateimanager")
else:
    wid = max(neu)
    wx, wy, ww, wh, _ = fenster()[wid]
    lauf.sag("  Dateimanager id=%d bei %d,%d %dx%d" % (wid, wx, wy, ww, wh))
    rel = lambda dx, dy: (wx + dx, wy + dy)

    # ------------------------------------------- 2. Zug ANHALTEN
    # Kein `ziehe()`: das laesst sofort wieder los. Hier wird
    # gedrueckt, gefahren, ANGEHALTEN und fotografiert.
    m = lauf.m
    m._maus(2)
    start = rel(320, 338)      # 'epsilon.txt' in der Tabelle
    m.gehe(start[0], start[1])
    tip_vor = tips()
    lauf.sag("-- 2. druecken und ziehen --")
    lauf.sag("  Tip-Fenster VOR dem Zug: %s" % tip_vor)
    m.sag("mouse_button 1", 0.3)
    halt = []
    try:
        # erster Schritt: die Zeile verlassen (sonst kein K_DRAG)
        for schritt, (dx, dy) in enumerate([(0, -45), (-110, -5), (-100, 0), (-35, 10)]):
            m.sag("mouse_move %d %d" % (dx, dy), 0.25)
            time.sleep(1.5)
            t = tips()
            halt.append(t)
            lauf.sag("  nach Schritt %d: Tip-Fenster %s" % (schritt + 1, t))
            lauf.bild("02-zug-schritt%d" % (schritt + 1))
    finally:
        m.sag("mouse_button 0", 0.25)
        m.sag("mouse_button 0", 0.1)
        m._maus(1)
    time.sleep(2.5)
    lauf.bild("03-nach-loslassen")
    tip_nach = tips()
    lauf.sag("-- 3. nach dem Loslassen --")
    lauf.sag("  Tip-Fenster NACH dem Zug: %s" % tip_nach)

    waehrend = set()
    for t in halt:
        waehrend |= set(t)
    neu_tip = sorted(waehrend - set(tip_vor))
    lauf.sag("== BEFUND ==")
    lauf.sag("  Schild waehrend des Zugs: %s" % ("JA %s" % neu_tip if neu_tip else "NEIN"))
    lauf.sag("  Schild danach weg: %s" % ("JA" if not (set(tip_nach) - set(tip_vor)) else "NEIN"))
    t = lauf.lies()
    lauf.sag("  expl: zieh %s" % re.findall(r"expl: zieh ([^\n]{0,50})", t)[-2:])

lauf.sag("== Ende DESIGN-3 ==")
