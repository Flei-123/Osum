# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-energie.py -- DREHBUCH (a): der Ausschalt-Knopf in der Oberflaeche.
#
# Punkt P-003. Die Funktion ist seit Runde ENERGIE (c0e4beed) auf main
# fertig; diese Runde baut sie NICHT nach, sondern BELEGT sie mit Bildern
# auf dem heutigen Stand -- das ist der Auftrag.
#
# WIE DIE ORTE ZUSTANDEKOMMEN, und warum nicht aus dem Protokoll:
# launcher.fi meldet in diesem Stand KEINE "rect id=..."-Zeilen mehr
# (pruef/oneshot.py hat sich darauf verlassen und faellt deshalb auf
# feste Zahlen zurueck). Der Fensterserver meldet aber sehr wohl die
# LAGE DES FENSTERS ("wm: fen ... lay=4" ist das Startmenue), und
# innerhalb dieses Fensters ist der Energieknopf unten links -- im Bild
# der Grundlinie gemessen bei (53, 738) auf dem Schirm, das Fenster
# steht bei (0,0) 387x294 ... bis 800. Also wird die Lage AUS DEM
# FENSTERRECHTECK gerechnet und nicht geraten: unten links, eine
# Knopfhoehe ueber dem unteren Rand.
#
# Der Weg ist der eines Menschen: Super druecken, das Energiemenue
# aufklappen, einen Punkt waehlen, die Rueckfrage ansehen -- und dann
# ABBRECHEN. Dieses Drehbuch schaltet absichtlich NICHT ab: es soll
# zeigen, dass der Weg da ist und dass die Rueckfrage davor steht.
import re
import time

lauf.sag("== (a) P-003: Ausschalten aus der Oberflaeche ==")


def fenster_lay(lay):
    """Das zuletzt gemeldete Fenster einer Ebene (lay=4 = Startmenue)."""
    f = re.findall(
        r"wm: fen i=\d+ id=(\d+) x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+) lay=%d" % lay,
        lauf.lies())
    return tuple(int(v) for v in f[-1]) if f else None


# --------------------------------------------------- 1. Das Startmenue
lauf.sag("Super-Taste druecken")
lauf.m.taste("meta_l")
time.sleep(3)
lauf.bild("startmenue")

men = fenster_lay(4)
lauf.sag("  Startmenue-Fenster (lay=4): %s" % (men,))
if not men:
    lauf.sag("  ABBRUCH: kein Startmenue")
else:
    mid, mx, my, mw, mh = men
    # Der Energieknopf: unten links im Menuefenster. Aus dem Bild der
    # Grundlinie gemessen: Knopfmitte 33 Bildpunkte ueber der Unterkante,
    # 53 vom linken Rand.
    ex, ey = mx + 53, my + mh - 33
    lauf.sag("Energieknopf bei %d,%d" % (ex, ey))
    vor = set(lauf.wins())
    lauf.m.klick_auf(ex, ey)
    time.sleep(3)
    lauf.bild("energiemenue")

    # Ein aufgeklapptes Menue ist ein NEUES Fenster. Welches ist dazu
    # gekommen? (wins() liest "wlib: win", das dieser Stand nicht
    # schreibt -- deshalb ueber den Fensterserver.)
    alle = re.findall(
        r"wm: fen i=\d+ id=(\d+) x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+) lay=(\d+)",
        lauf.lies())
    ids = {}
    for f in alle:
        ids[f[0]] = tuple(int(v) for v in f[1:])   # x,y,w,h,lay
    lauf.sag("  Fenster jetzt: %s" % sorted(ids.keys()))
    # Das Energiemenue ist das JUENGSTE Fenster mit kleiner Hoehe.
    # v = (x, y, w, h, lay) -- die Ebene wird hier nicht gebraucht.
    kandidaten = [(i, v[:4]) for i, v in ids.items()
                  if int(i) > mid and v[3] < 200]
    lauf.sag("  Menuekandidaten (juenger als das Startmenue, flach): %s"
             % kandidaten)

    if kandidaten:
        ki, (kx, ky, kw, kh) = kandidaten[-1]
        zh = kh // 3         # Ausschalten, Neustart, Abmelden
        px, py = kx + kw // 2, ky + zh // 2
        lauf.sag("Energiemenue id=%s bei %d,%d %dx%d -> Punkt 0 bei %d,%d"
                 % (ki, kx, ky, kw, kh, px, py))
        lauf.m.klick_auf(px, py)
        time.sleep(3)
        lauf.bild("rueckfrage")

        # --------------------------------------------- ABBRECHEN
        lauf.sag("Flucht -> abbrechen (die Maschine soll weiterlaufen)")
        lauf.m.taste("esc")
        time.sleep(3)
        lauf.bild("abgebrochen")
    else:
        lauf.sag("  kein zweites Fenster -- Menue klappte nicht auf")

t = lauf.lies()
lauf.sag("--- Protokollspuren ---")
for muster, was in ((r"energie auf", "Menue aufgeklappt"),
                    (r"energie wahl=(\d+)", "Punkt gewaehlt"),
                    (r"energie frage=(\d+)", "Rueckfrage"),
                    (r"energie tat (\d+)", "TAT (muss leer sein)"),
                    (r"energie abbruch", "Abbruch"),
                    (r"init: herunterfahren", "init faehrt herunter"),
                    (r"power: acpi", "ACPI S5")):
    r = re.findall(muster, t)
    lauf.sag("  %-24s %s" % (was, ("%dx %s" % (len(r), r[:3])) if r else "-"))
lauf.sag("== Ende (a) ==")
