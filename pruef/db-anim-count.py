# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-anim-count.py -- PUNKT 3, DER ZAHLENBELEG.
#
# `wmanim` ist eine VORFUEHRUNG: der Kern laesst dort selbst ein Fenster
# auf- und zugehen und ruft dafuer `open_anim`/`close_anim` direkt. Die
# Zahlen daraus beweisen nur, dass der Unterbau lebt -- sie beweisen
# NICHT, dass ein Fenster, das ein MENSCH oeffnet, sich bewegt.
#
# Genau das ist der Unterschied dieser Runde, und genau das misst diese
# Datei: sie ruft `wm.anims`/`wm.anim_frames` AUF ANFORDERUNG ueber die
# serielle Leitung ab, waehrend ein Mensch (das Drehbuch) Fenster
# oeffnet, minimiert und schliesst. Vorher MUSS hier 0 stehen -- die
# drei Einstiege wurden nirgends aufgerufen --, nachher nicht.
#
# Gelesen wird die Zahl aus `qs:`-artigen Zeilen, die der Server auf
# Anforderung schreibt. Gibt es sie in diesem Aufbau nicht, faellt das
# Drehbuch auf den Bildvergleich zurueck: ein Fenster MITTEN in der
# Bewegung ist kleiner als danach, und das ist in Bildpunkten messbar.
import re
import time

lauf.say("== PUNKT 3, Zahlenbeleg: bewegen sich ECHTE Fenster? ==")


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


# ------------------------------------------------------ ein Fenster auf
vor = set(window().keys())
lauf.m.key_press("meta_l")
time.sleep(3)
men = [(i, v) for i, v in window().items() if v[4] == 4]
if not men:
    lauf.say("KEIN STARTMENUE -- Abbruch")
else:
    mid, (mx, my, mw, mh, _) = men[-1]
    lauf.m.klick_auf(mx + 207, my + 60)
    time.sleep(1)
    for _ in range(24):
        lauf.m.key_press("backspace")
    lauf.m.tippe("nedit")
    time.sleep(2)

    # DIE SERIE. Sechs Bilder so schnell wie moeglich nach der Eingabe:
    # die Bewegung dauert 160 ms, also faellt mindestens eines mitten
    # hinein, wenn es eine gibt.
    lauf.m.key_press("ret")
    for k in range(6):
        lauf.image("auf-%d" % k)
    time.sleep(6)
    lauf.image("auf-fertig")

    renewed = [i for i in window().keys() if i not in vor and i != mid]
    if not renewed:
        lauf.say("kein neues Fenster -- Abbruch")
    else:
        wid = max(renewed)
        wx, wy, ww, wh, _ = window()[wid]
        lauf.say("Fenster id=%d bei %d,%d %dx%d" % (wid, wx, wy, ww, wh))

        # ------------------------------------------------ minimieren
        lauf.say("-- minimieren --")
        lauf.m.klick_auf(wx + ww - 74, wy + 12)
        for k in range(6):
            lauf.image("min-%d" % k)
        time.sleep(4)
        lauf.image("min-fertig")

lauf.say("== Ende ==")
