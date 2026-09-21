# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-minimieren.py -- PUNKT 3: DAS MINIMIEREN, MITTEN IN DER
# BEWEGUNG FOTOGRAFIERT.
#
# Der vorige Versuch hat die Bewegung verfehlt, und zwar aus einem
# Grund, der sich messen laesst: ein Bild ueber den QEMU-Monitor kostet
# hier rund eine Sekunde, die Bewegung dauert 500 ms (motion=500, der
# Hoechstwert). Sechs Bilder hintereinander treffen sie deshalb nicht --
# das erste kommt zu frueh, das zweite zu spaet.
#
# DIE LOESUNG IST NICHT "schneller fotografieren", sondern den Klick und
# das Bild ZUSAMMENZULEGEN: erst das Fenster suchen, den Zeiger auf den
# Knopf stellen, und dann Klick und Aufnahme ohne irgendetwas dazwischen.
#
# Gemessen wird die AUSDEHNUNG der Fensterflaeche. Waehrend des
# Minimierens ist sie kleiner als vorher UND ihr Mittelpunkt ist zum
# Leistenknopf hin verschoben -- das ist der Unterschied zwischen
# "schrumpft in der Mitte" (vorher) und "fliegt zum eigenen Knopf"
# (diese Runde).
import re
import time

lauf.sag("== PUNKT 3: das Minimieren, mitten in der Bewegung ==")


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
    lauf.m.taste("ret")
    time.sleep(8)          # ganz aufgehen lassen
    lauf.bild("a-vorher")

    neu = [i for i in fenster().keys() if i not in vor and i != mid]
    if not neu:
        lauf.sag("kein neues Fenster -- Abbruch")
    else:
        wid = max(neu)
        wx, wy, ww, wh, _ = fenster()[wid]
        lauf.sag("Fenster id=%d bei %d,%d %dx%d" % (wid, wx, wy, ww, wh))

        # DIE DREI KNOEPFE. `cap_at` legt sie rechts in die Titelleiste;
        # gemessen im Bild sitzt das Kreuz bei x = wx+ww-14, und die
        # drei stehen 30 auseinander. CAP_MIN ist der LINKE.
        knx = wx + ww - 74
        kny = wy + 12
        lauf.sag("Minimierknopf vermutet bei %d,%d" % (knx, kny))

        # Zeiger HIN, ohne zu klicken -- das kostet die Zeit, die sonst
        # die Bewegung auffressen wuerde.
        lauf.m.gehe(knx, kny)
        time.sleep(1)
        lauf.bild("b-zeiger-auf-knopf")

        # Und jetzt Klick + Bild so dicht wie es geht.
        lauf.m.klick_auf(knx, kny)
        lauf.bild("c-mitten-drin")
        lauf.bild("d-kurz-danach")
        time.sleep(4)
        lauf.bild("e-fertig")

        noch = wid in fenster()
        lauf.sag("Fenster danach noch gelistet: %s" % noch)

lauf.sag("== Ende ==")
