# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-theme.py -- PUNKT 2: ERREICHT EIN THEMENWECHSEL WIRKLICH JEDES
# PROGRAMM?
#
# Die Frage aus Justins Liste ist nicht "wie viele harte Farben stehen
# im Quelltext" -- das ist ein Hilfsmass. Die Frage ist:
#
#     Wenn ich das Schema wechsle, aendert sich DANN AUCH der Editor,
#     der Dateimanager und das Einstellungsfenster?
#
# Ein Programm, das an der Bibliothek vorbei malt, bleibt beim Wechsel
# hell stehen, waehrend alles andere dunkel wird. Genau DAS ist im Bild
# zu sehen, und genau das misst dieses Drehbuch: es oeffnet drei
# Programme, fotografiert sie, und der Aufrufer vergleicht dieselben
# Bilder aus einem hellen und einem dunklen Lauf.
#
# Gemessen wird je Fenster die HAEUFIGSTE FARBE seiner Flaeche. Bleibt
# sie ueber beide Laeufe gleich, hat der Themenwechsel dieses Fenster
# NICHT erreicht.
import re
import time

lauf.say("== PUNKT 2: erreicht der Themenwechsel jedes Programm? ==")


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


def starte(name):
    """Ueber das Startmenue suchen und mit Eingabe starten."""
    vor = set(window().keys())
    lauf.m.key_press("meta_l")
    time.sleep(3)
    men = [(i, v) for i, v in window().items() if v[4] == 4]
    if not men:
        lauf.say("   KEIN STARTMENUE fuer %s" % name)
        return None
    mid, (mx, my, mw, mh, _) = men[-1]
    lauf.m.klick_auf(mx + 207, my + 60)
    time.sleep(1)
    for _ in range(24):
        lauf.m.key_press("backspace")
    time.sleep(1)
    lauf.m.tippe(name)
    time.sleep(2)
    lauf.m.key_press("ret")
    time.sleep(6)
    renewed = [i for i in window().keys() if i not in vor and i != mid]
    if not renewed:
        lauf.say("   %s ist nicht aufgegangen" % name)
        return None
    wid = max(renewed)
    lauf.say("   %s -> Fenster id=%d %s" % (name, wid, window()[wid]))
    return wid


lauf.image("a-schreibtisch")

for prog in ("nedit", "explorer", "settings"):
    lauf.say("-- %s --" % prog)
    wid = starte(prog)
    if wid:
        lauf.image("b-%s" % prog)

lauf.say("== Ende Punkt 2 ==")
