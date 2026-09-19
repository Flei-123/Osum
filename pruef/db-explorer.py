# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-explorer.py -- DREHBUCH: den Dateimanager ansehen.
#
# Vor jeder Aenderung am Explorer: wie sieht er HEUTE aus, und was
# meldet er? Das ist die Grundlinie fuer (b) Drag-and-Drop, (c) Reiter
# und (f) das Design-Urteil. Ohne dieses Bild waere jede spaetere
# Aussage ueber "besser" oder "schlechter" eine Behauptung.
#
# Der Dateimanager wird aus dem Startmenue gestartet (zweiter Eintrag,
# "File Explorer") -- derselbe Weg, den ein Mensch nimmt.
import re
import time

lauf.sag("== Dateimanager ansehen (Grundlinie fuer b, c, f) ==")


def fenster():
    """Alle Fenster, die der Server zuletzt gemeldet hat: id -> (x,y,w,h,lay)."""
    alle = re.findall(
        r"wm: fen i=\d+ id=(\d+) x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+) lay=(\d+)",
        lauf.lies())
    d = {}
    for f in alle:
        d[int(f[0])] = tuple(int(v) for v in f[1:])
    return d


vorher = set(fenster().keys())
lauf.sag("Fenster vor dem Start: %s" % sorted(vorher))

# ------------------------------------------------ Startmenue oeffnen
lauf.m.taste("meta_l")
time.sleep(3)
lauf.bild("startmenue")

men = None
for i, v in fenster().items():
    if v[4] == 4:                     # lay=4 ist das Startmenue
        men = (i, v)
if not men:
    lauf.sag("ABBRUCH: kein Startmenue")
else:
    mid, (mx, my, mw, mh, _) = men
    lauf.sag("Startmenue id=%d bei %d,%d %dx%d" % (mid, mx, my, mw, mh))
    # Die Programmliste beginnt unter dem Suchfeld. Aus dem Bild der
    # Grundlinie gemessen: erster Eintrag "Editor" auf y=485 (Schirm),
    # jeder weitere 38 Bildpunkte tiefer. "File Explorer" ist der ZWEITE.
    zx, zy = mx + 100, my + 131
    lauf.sag("Klick auf 'File Explorer' bei %d,%d" % (zx, zy))
    lauf.m.klick_auf(zx, zy)
    time.sleep(2)
    # Ein Klick waehlt nur aus -- geoeffnet wird mit "Run" oder Enter.
    lauf.m.taste("ret")
    time.sleep(6)
    lauf.bild("explorer-offen")

    neu = [i for i in fenster().keys() if i not in vorher and i != mid]
    lauf.sag("neue Fenster: %s" % sorted(neu))
    for i in sorted(neu):
        lauf.sag("   id=%d %s" % (i, fenster()[i]))

t = lauf.lies()
lauf.sag("--- was der Dateimanager meldet ---")
for muster in (r"explorer: ready", r"explorer: orte n=(\d+) traeger=(\d+)",
               r"explorer: rect", r"expl: zieh", r"expl: drop"):
    r = re.findall(muster, t)
    lauf.sag("  %-34s %s" % (muster, ("%dx %s" % (len(r), r[:3])) if r else "-"))
lauf.sag("== Ende ==")
