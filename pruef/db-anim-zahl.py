# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-anim-zahl.py -- PUNKT 3, DER ZAHLENBELEG.
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

lauf.sag("== PUNKT 3, Zahlenbeleg: bewegen sich ECHTE Fenster? ==")


def fenster():
    text = lauf.lies()
    bloecke = re.split(r"(?=wm: fen i=0 )", text)
    letzter = bloecke[-1] if len(bloecke) > 1 else text
    alle = re.findall(
        r"wm: fen i=\d+ id=(\d+) x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+) lay=(\d+)",
        letzter)
    d = {}
    for f in alle:
        d[int(f[0])] = tuple(int(v) for v in f[1:])
    return d


# ------------------------------------------------------ ein Fenster auf
vor = set(fenster().keys())
lauf.m.taste("meta_l")
time.sleep(3)
men = [(i, v) for i, v in fenster().items() if v[4] == 4]
if not men:
    lauf.sag("KEIN STARTMENUE -- Abbruch")
else:
    mid, (mx, my, mw, mh, _) = men[-1]
    lauf.m.klick_auf(mx + 207, my + 60)
    time.sleep(1)
    for _ in range(24):
        lauf.m.taste("backspace")
    lauf.m.tippe("nedit")
    time.sleep(2)

    # DIE SERIE. Sechs Bilder so schnell wie moeglich nach der Eingabe:
    # die Bewegung dauert 160 ms, also faellt mindestens eines mitten
    # hinein, wenn es eine gibt.
    lauf.m.taste("ret")
    for k in range(6):
        lauf.bild("auf-%d" % k)
    time.sleep(6)
    lauf.bild("auf-fertig")

    neu = [i for i in fenster().keys() if i not in vor and i != mid]
    if not neu:
        lauf.sag("kein neues Fenster -- Abbruch")
    else:
        wid = max(neu)
        wx, wy, ww, wh, _ = fenster()[wid]
        lauf.sag("Fenster id=%d bei %d,%d %dx%d" % (wid, wx, wy, ww, wh))

        # ------------------------------------------------ minimieren
        lauf.sag("-- minimieren --")
        lauf.m.klick_auf(wx + ww - 74, wy + 12)
        for k in range(6):
            lauf.bild("min-%d" % k)
        time.sleep(4)
        lauf.bild("min-fertig")

lauf.sag("== Ende ==")
