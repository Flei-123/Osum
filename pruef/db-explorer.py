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

lauf.say("== Dateimanager ansehen (Grundlinie fuer b, c, f) ==")


def window():
    """Alle Fenster, die der Server zuletzt gemeldet hat: id -> (x,y,w,h,lay)."""
    everything = re.findall(
        r"wm: fen i=\d+ id=(\d+) x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+) lay=(\d+)",
        lauf.read_text())
    d = {}
    for f in everything:
        d[int(f[0])] = tuple(int(v) for v in f[1:])
    return d


vorher = set(window().keys())
lauf.say("Fenster vor dem Start: %s" % sorted(vorher))

# ------------------------------------------------ Startmenue oeffnen
lauf.m.key_press("meta_l")
time.sleep(3)
lauf.image("startmenue")

men = None
for i, v in window().items():
    if v[4] == 4:                     # lay=4 ist das Startmenue
        men = (i, v)
if not men:
    lauf.say("ABBRUCH: kein Startmenue")
else:
    mid, (mx, my, mw, mh, _) = men
    lauf.say("Startmenue id=%d bei %d,%d %dx%d" % (mid, mx, my, mw, mh))
    # Die Programmliste beginnt unter dem Suchfeld. Aus dem Bild der
    # Grundlinie gemessen: erster Eintrag "Editor" auf y=485 (Schirm),
    # jeder weitere 38 Bildpunkte tiefer. "File Explorer" ist der ZWEITE.
    zx, zy = mx + 100, my + 131
    lauf.say("Klick auf 'File Explorer' bei %d,%d" % (zx, zy))
    lauf.m.klick_auf(zx, zy)
    time.sleep(2)
    # Ein Klick waehlt nur aus -- geoeffnet wird mit "Run" oder Enter.
    lauf.m.key_press("ret")
    time.sleep(6)
    lauf.image("explorer-offen")

    renewed = [i for i in window().keys() if i not in vorher and i != mid]
    lauf.say("neue Fenster: %s" % sorted(renewed))
    for i in sorted(renewed):
        lauf.say("   id=%d %s" % (i, window()[i]))

t = lauf.read_text()
lauf.say("--- was der Dateimanager meldet ---")
for muster in (r"explorer: ready", r"explorer: orte n=(\d+) traeger=(\d+)",
               r"explorer: rect", r"expl: zieh", r"expl: drop"):
    r = re.findall(muster, t)
    lauf.say("  %-34s %s" % (muster, ("%dx %s" % (len(r), r[:3])) if r else "-"))
lauf.say("== Ende ==")
