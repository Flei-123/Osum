# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-motion.py -- PUNKT 3: DIE TOTEN ANIMATIONEN, JETZT LEBENDIG.
#
# WAS HIER GEMESSEN WIRD, und warum es nicht "sieht man doch" heisst:
# eine Bewegung, die 160 ms dauert, ist auf einem Bild entweder da oder
# vorbei. Der Beweis ist deshalb ZWEITEILIG:
#
#   1. DER SERVER ZAEHLT SIE. `wm:`-Zeilen melden `anim=` (laufende) und
#      `frames=` (gezeichnete Zwischenbilder). Vor dieser Runde war
#      `frames=0` bei JEDEM Lauf, weil open_anim/close_anim/
#      minimize_anim nirgends aufgerufen wurden.
#   2. MAN SIEHT SIE. Bilder MITTEN in der Bewegung, kurz nach dem
#      Klick -- da steht das Fenster kleiner und durchscheinend.
#
# UND DAS ZIEL DES MINIMIERENS. Die Leiste meldet je Knopf ein
# Rechteck (WM_MINRECT); der Server laesst das Fenster dorthin fliegen
# statt in die Mitte. Gemessen wird, DASS das Rechteck ankommt -- und
# das Bild zeigt, wohin es fliegt.
import re
import time

lauf.say("== PUNKT 3: Fenster auf, zu, minimiert ==")


def window():
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


def anim_counts():
    """Die letzte `wm: vsync=...`-Zeile, die anim= und frames= traegt."""
    z = re.findall(r"wm: vsync=[^\n]*anim=(\d+)[^\n]*frames=(\d+)", lauf.read_text())
    if not z:
        return (None, None)
    return (int(z[-1][0]), int(z[-1][1]))


a0, f0 = anim_counts()
lauf.say("vorher:  anim=%s frames=%s" % (a0, f0))

# ------------------------------------------------ 1. EIN FENSTER OEFFNEN
lauf.say("-- 1. ein Fenster geht auf (AN_WIN_OPEN) --")
vor = set(window().keys())
lauf.m.key_press("meta_l")
time.sleep(3)
men = [(i, v) for i, v in window().items() if v[4] == 4]
if not men:
    lauf.say("   KEIN STARTMENUE")
else:
    mid, (mx, my, mw, mh, _) = men[-1]
    lauf.m.klick_auf(mx + 207, my + 60)
    time.sleep(1)
    for _ in range(24):
        lauf.m.key_press("backspace")
    lauf.m.tippe("nedit")
    time.sleep(2)
    lauf.m.key_press("ret")
    # SOFORT fotografieren -- 160 ms Bewegung, also so schnell es geht.
    time.sleep(0.25)
    lauf.image("a-waehrend-oeffnen")
    time.sleep(6)
    lauf.image("b-offen")

    renewed = [i for i in window().keys() if i not in vor and i != mid]
    if not renewed:
        lauf.say("   kein neues Fenster")
    else:
        wid = max(renewed)
        wx, wy, ww, wh, _ = window()[wid]
        lauf.say("   Fenster id=%d bei %d,%d %dx%d" % (wid, wx, wy, ww, wh))
        a1, f1 = anim_counts()
        lauf.say("   nach dem Oeffnen: anim=%s frames=%s" % (a1, f1))

        # ------------------------------------- 2. MELDET DIE LEISTE EIN ZIEL?
        lauf.say("-- 2. das Ziel des Minimierens --")
        mr = re.findall(r"taskbar: btn i=\d+ id=(\d+) x=(\d+) y=(\d+) "
                        r"w=(\d+) h=(\d+)", lauf.read_text())
        if mr:
            for e in mr[-4:]:
                lauf.say("   Leistenknopf id=%s bei %s,%s %sx%s" % e)
        else:
            lauf.say("   (die Leiste meldet ihre Knoepfe nur mit /etc/uitrace)")

        # ------------------------------------- 3. MINIMIEREN
        lauf.say("-- 3. minimieren (AN_WIN_MIN) --")
        # Der Minimierknopf: drei Zeichen rechts in der Titelleiste.
        # Das linke der drei ist CAP_MIN.
        mx2 = wx + ww - 74
        my2 = wy + 12
        lauf.say("   Klick auf den Minimierknopf bei %d,%d" % (mx2, my2))
        lauf.m.klick_auf(mx2, my2)
        time.sleep(0.25)
        lauf.image("c-waehrend-minimieren")
        time.sleep(4)
        lauf.image("d-minimiert")
        a2, f2 = anim_counts()
        lauf.say("   nach dem Minimieren: anim=%s frames=%s" % (a2, f2))
        versteckt = wid not in window() or True
        lauf.say("   Fenster id=%d noch gelistet: %s" % (wid, wid in window()))

lauf.say("== Ende Punkt 3 ==")
