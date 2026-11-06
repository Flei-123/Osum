# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-dragframe.py -- RUNDE DESIGN-3: das Zugbild am Zeiger.
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

lauf.say("== DESIGN-3: Zugbild am Zeiger ==")


def window():
    # NUR DER LETZTE BLOCK ZAEHLT. Der Fensterserver schreibt seine
    # Liste immer wieder neu; wer das ganze Protokoll sammelt, sieht
    # auch Fenster, die laengst zu sind -- und haelt ein sauber
    # geschlossenes Schild faelschlich fuer haengengeblieben.
    text = lauf.read_text()
    bloecke = re.split(r"(?=wm: fen i=0 )", text)
    last_item = bloecke[-1] if len(bloecke) > 1 else text
    everything = re.findall(
        r"wm: fen i=\d+ id=(\d+) x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+) lay=(\d+)",
        last_item)
    d = {}
    for f in everything:
        d[int(f[0])] = tuple(int(v) for v in f[1:])
    return d


def tips():
    return sorted([i for i, v in window().items() if v[4] == L_TIP])


def startmenue_punkt(name):
    lauf.m.key_press("meta_l")
    time.sleep(3)
    men = [(i, v) for i, v in window().items() if v[4] == 4]
    if not men:
        lauf.say("  KEIN STARTMENUE")
        return False
    mid, (mx, my, mw, mh, _) = men[-1]
    lauf.m.klick_auf(mx + 207, my + 60)
    time.sleep(1)
    for _ in range(24):
        lauf.m.key_press("backspace")
    time.sleep(1)
    lauf.m.tippe(name)
    time.sleep(2)
    lauf.m.key_press("ret")
    time.sleep(5)
    return True


# ------------------------------------------------ 1. Dateimanager
lauf.say("-- 1. Dateimanager starten --")
vor = set(window().keys())
startmenue_punkt("Datei")
lauf.image("01-explorer")
renewed = [i for i in window().keys() if i not in vor]
lauf.say("  neue Fenster: %s" % sorted(renewed))
if not renewed:
    lauf.say("ABBRUCH: kein Dateimanager")
else:
    wid = max(renewed)
    wx, wy, ww, wh, _ = window()[wid]
    lauf.say("  Dateimanager id=%d bei %d,%d %dx%d" % (wid, wx, wy, ww, wh))
    rel = lambda dx, dy: (wx + dx, wy + dy)

    # ------------------------------------------- 2. Zug ANHALTEN
    # Kein `ziehe()`: das laesst sofort wieder los. Hier wird
    # gedrueckt, gefahren, ANGEHALTEN und fotografiert.
    m = lauf.m
    m._mouse(2)
    start = rel(320, 338)      # 'epsilon.txt' in der Tabelle
    m.go_to(start[0], start[1])
    tip_vor = tips()
    lauf.say("-- 2. druecken und ziehen --")
    lauf.say("  Tip-Fenster VOR dem Zug: %s" % tip_vor)
    m.say("mouse_button 1", 0.3)
    halt = []
    try:
        # erster Schritt: die Zeile verlassen (sonst kein K_DRAG)
        for schritt, (dx, dy) in enumerate([(0, -45), (-110, -5), (-100, 0), (-35, -8)]):
            m.say("mouse_move %d %d" % (dx, dy), 0.25)
            time.sleep(1.5)
            t = tips()
            halt.append(t)
            lauf.say("  nach Schritt %d: Tip-Fenster %s" % (schritt + 1, t))
            lauf.image("02-zug-schritt%d" % (schritt + 1))
    finally:
        m.say("mouse_button 0", 0.25)
        m.say("mouse_button 0", 0.1)
        m._mouse(1)
    time.sleep(2.5)
    lauf.image("03-nach-loslassen")
    tip_nach = tips()
    lauf.say("-- 3. nach dem Loslassen --")
    lauf.say("  Tip-Fenster NACH dem Zug: %s" % tip_nach)

    waehrend = set()
    for t in halt:
        waehrend |= set(t)
    renewed_tip = sorted(waehrend - set(tip_vor))
    lauf.say("== BEFUND ==")
    lauf.say("  Schild waehrend des Zugs: %s" % ("JA %s" % renewed_tip if renewed_tip else "NEIN"))
    lauf.say("  Schild danach weg: %s" % ("JA" if not (set(tip_nach) - set(tip_vor)) else "NEIN"))
    t = lauf.read_text()
    lauf.say("  expl: zieh %s" % re.findall(r"expl: zieh ([^\n]{0,50})", t)[-2:])

lauf.say("== Ende DESIGN-3 ==")
