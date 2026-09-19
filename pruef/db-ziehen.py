# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-ziehen.py -- DREHBUCH (b): Ziehen und Ablegen im Dateimanager.
#
# Gemessen wird der Weg eines Menschen: eine Datei in der Tabelle
# anfassen, mit gedrueckter Taste fahren, ueber dem Ziel loslassen.
# Drei Ziele, drei Laeufe in EINEM Boot:
#
#   1. auf einen ORDNER in der Tabelle   -> hinein verschoben
#   2. auf einen ORT in der Leiste        -> in diesen Ordner verschoben
#   3. auf den PAPIERKORB in der Leiste   -> in den Korb geworfen
#
# DER BEWEIS IST NICHT DAS BILD ALLEIN. Ein Bild zeigt, dass eine Zeile
# verschwunden ist -- nicht, wohin. Deshalb liest dieses Drehbuch
# zusaetzlich die Meldungen des Dateimanagers ("expl: droport ... ->
# korb", "expl: drop* rc=0") und der Bericht am Ende liest das
# Plattenabbild vom Wirt aus.
import re
import time

lauf.sag("== (b) Ziehen und Ablegen ==")


def fenster():
    alle = re.findall(
        r"wm: fen i=\d+ id=(\d+) x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+) lay=(\d+)",
        lauf.lies())
    d = {}
    for f in alle:
        d[int(f[0])] = tuple(int(v) for v in f[1:])
    return d


def rechtecke():
    """Was der Dateimanager ueber seine Bedienelemente meldet.

    Nur mit /etc/uitrace im Abbild -- sonst schweigt er (s_dbg,
    explorer.fi:309). Das ist die Lehre aus RUNDE CLIP-2.
    """
    return re.findall(
        r"explorer: rect id=(\d+) kind=(\d+) x=(-?\d+) y=(-?\d+) "
        r"w=(\d+) h=(\d+)", lauf.lies())


# ------------------------------------------------ Dateimanager starten
vorher = set(fenster().keys())
lauf.m.taste("meta_l")
time.sleep(3)
men = [(i, v) for i, v in fenster().items() if v[4] == 4]
if not men:
    lauf.sag("ABBRUCH: kein Startmenue")
else:
    mid, (mx, my, mw, mh, _) = men[-1]
    lauf.m.klick_auf(mx + 100, my + 131)
    time.sleep(2)
    lauf.m.taste("ret")
    time.sleep(7)
    lauf.bild("explorer")

    neu = [i for i in fenster().keys() if i not in vorher and i != mid]
    if not neu:
        lauf.sag("ABBRUCH: kein Dateimanager")
    else:
        wid = max(neu)
        wx, wy, ww, wh, _ = fenster()[wid]
        lauf.sag("Dateimanager id=%d bei %d,%d %dx%d" % (wid, wx, wy, ww, wh))

        r = rechtecke()
        lauf.sag("gemeldete Rechtecke: %d" % len(r))
        for e in r[:14]:
            lauf.sag("   id=%s kind=%s  %s,%s %sx%s" % e)

        # Aus dem Bild der Grundlinie gemessen (Fenster 70,70 660x430):
        #   Ortsleiste: x 80..243, Home y=198, je Zeile 20 hoch
        #   Tabelle:    x 250..723, erste Zeile y=221, je Zeile 20
        # Die Zahlen werden RELATIV zum Fenster gerechnet, damit sie
        # auch gelten, wenn das Fenster woanders steht.
        rel = lambda dx, dy: (wx + dx, wy + dy)

        def zug(von, nach, was):
            """Druecken, fahren, loslassen -- mit klick.py's `ziehe`.

            NICHT selbst gebaut: `Maschine.ziehe` schaltet auf die
            RELATIVE Maus um, teilt die Strecke ohne Rest auf und
            laesst die Taste in einem `finally` wieder los. Beide
            Eigenschaften sind dort als Fehler gemessen und behoben
            worden (RUNDE TUERSCHLOSS); sie hier noch einmal zu
            schreiben hiesse, beide Fehler noch einmal zu machen.
            """
            lauf.sag("ZUG: %s   %s -> %s" % (was, von, nach))
            lauf.m.ziehe(von[0], von[1], nach[0], nach[1])
            time.sleep(2.5)

        # ---------------------------------------- 1. auf einen Ordner
        # "alpha.txt" ist Zeile 3 der Tabelle (bilder, notizen,
        # alpha.txt ...), Ziel ist "bilder" = Zeile 1.
        lauf.bild("vor-zug1")
        zug(rel(320, 191), rel(320, 151), "alpha.txt -> Ordner bilder")
        lauf.bild("nach-zug1")
        t = lauf.lies()
        lauf.sag("  expl: zieh   %s" % re.findall(r"expl: zieh ([^\n]{0,60})", t)[-3:])
        lauf.sag("  expl: drop   %s" % re.findall(r"expl: drop ([^\n]{0,70})", t)[-3:])
        lauf.sag("  expl: drop*  %s" % re.findall(r"expl: drop\* rc=(\d+)", t)[-3:])

        # ------------------------------------- 2. auf einen Ort (Pictures)
        lauf.bild("vor-zug2")
        zug(rel(320, 171), rel(140, 147), "beta.txt -> Ort Pictures")
        lauf.bild("nach-zug2")
        t = lauf.lies()
        lauf.sag("  droport      %s" % re.findall(r"expl: droport ([^\n]{0,70})", t)[-3:])
        lauf.sag("  droport rc=  %s" % re.findall(r"expl: droport rc=(\d+)", t)[-3:])

        # ------------------------------------- 3. auf den Papierkorb
        lauf.bild("vor-zug3")
        zug(rel(320, 171), rel(140, 187), "eine Datei -> Papierkorb")
        lauf.bild("nach-zug3")
        t = lauf.lies()
        lauf.sag("  droport      %s" % re.findall(r"expl: droport ([^\n]{0,70})", t)[-3:])
        lauf.sag("  in den Korb  %s" % re.findall(r"trash rc=(\d+)", t)[-3:])

t = lauf.lies()
lauf.sag("--- Bilanz der Meldungen ---")
for muster, was in ((r"expl: zieh", "Ziehen angefangen"),
                    (r"expl: drop ", "Ablegen Tabelle/Baum"),
                    (r"expl: drop\* rc=(\d+)", "davon vollzogen"),
                    (r"expl: droport", "Ablegen Ortsleiste"),
                    (r"expl: ort nimmt nix", "Ort nimmt nichts"),
                    (r"expl: ort gleich", "schon dort"),
                    (r"trash rc=(\d+)", "in den Papierkorb")):
    r = re.findall(muster, t)
    lauf.sag("  %-24s %s" % (was, ("%dx %s" % (len(r), r[:3])) if r else "-"))
lauf.sag("== Ende (b) ==")
