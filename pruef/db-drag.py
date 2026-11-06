# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-drag.py -- DREHBUCH (b): Ziehen und Ablegen im Dateimanager.
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

lauf.say("== (b) Ziehen und Ablegen ==")


def window():
    everything = re.findall(
        r"wm: fen i=\d+ id=(\d+) x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+) lay=(\d+)",
        lauf.read_text())
    d = {}
    for f in everything:
        d[int(f[0])] = tuple(int(v) for v in f[1:])
    return d


def rechtecke():
    """Was der Dateimanager ueber seine Bedienelemente meldet.

    Nur mit /etc/uitrace im Abbild -- sonst schweigt er (s_dbg,
    explorer.fi:309). Das ist die Lehre aus RUNDE CLIP-2.
    """
    return re.findall(
        r"explorer: rect id=(\d+) kind=(\d+) x=(-?\d+) y=(-?\d+) "
        r"w=(\d+) h=(\d+)", lauf.read_text())


# ------------------------------------------------ Dateimanager starten
vorher = set(window().keys())
lauf.m.key_press("meta_l")
time.sleep(3)
men = [(i, v) for i, v in window().items() if v[4] == 4]
if not men:
    lauf.say("ABBRUCH: kein Startmenue")
else:
    mid, (mx, my, mw, mh, _) = men[-1]
    lauf.m.klick_auf(mx + 100, my + 131)
    time.sleep(2)
    lauf.m.key_press("ret")
    time.sleep(7)
    lauf.image("explorer")

    renewed = [i for i in window().keys() if i not in vorher and i != mid]
    if not renewed:
        lauf.say("ABBRUCH: kein Dateimanager")
    else:
        wid = max(renewed)
        wx, wy, ww, wh, _ = window()[wid]
        lauf.say("Dateimanager id=%d bei %d,%d %dx%d" % (wid, wx, wy, ww, wh))

        r = rechtecke()
        lauf.say("gemeldete Rechtecke: %d" % len(r))
        for e in r[:14]:
            lauf.say("   id=%s kind=%s  %s,%s %sx%s" % e)

        # Aus dem Bild der Grundlinie gemessen (Fenster 70,70 660x430):
        #   Ortsleiste: x 80..243, Home y=198, je Zeile 20 hoch
        #   Tabelle:    x 250..723, erste Zeile y=221, je Zeile 20
        # Die Zahlen werden RELATIV zum Fenster gerechnet, damit sie
        # auch gelten, wenn das Fenster woanders steht.
        rel = lambda dx, dy: (wx + dx, wy + dy)

        def zug(von, nach, was):
            """Druecken, fahren, loslassen -- mit click_driver.py's `ziehe`.

            NICHT selbst gebaut: `Maschine.ziehe` schaltet auf die
            RELATIVE Maus um, teilt die Strecke ohne Rest auf und
            laesst die Taste in einem `finally` wieder los. Beide
            Eigenschaften sind dort als Fehler gemessen und behoben
            worden (RUNDE TUERSCHLOSS); sie hier noch einmal zu
            schreiben hiesse, beide Fehler noch einmal zu machen.
            """
            lauf.say("ZUG: %s   %s -> %s" % (was, von, nach))
            lauf.m.ziehe(von[0], von[1], nach[0], nach[1])
            time.sleep(2.5)

        # ---------------------------------------- 1. auf einen Ordner
        # "alpha.txt" ist Zeile 3 der Tabelle (bilder, notizen,
        # alpha.txt ...), Ziel ist "bilder" = Zeile 1.
        lauf.image("vor-zug1")
        zug(rel(320, 191), rel(320, 151), "alpha.txt -> Ordner bilder")
        lauf.image("nach-zug1")
        t = lauf.read_text()
        lauf.say("  expl: zieh   %s" % re.findall(r"expl: zieh ([^\n]{0,60})", t)[-3:])
        lauf.say("  expl: drop   %s" % re.findall(r"expl: drop ([^\n]{0,70})", t)[-3:])
        lauf.say("  expl: drop*  %s" % re.findall(r"expl: drop\* rc=(\d+)", t)[-3:])

        # ------------------------------------- 2. auf einen Ort (Pictures)
        lauf.image("vor-zug2")
        zug(rel(320, 171), rel(140, 147), "beta.txt -> Ort Pictures")
        lauf.image("nach-zug2")
        t = lauf.read_text()
        lauf.say("  droport      %s" % re.findall(r"expl: droport ([^\n]{0,70})", t)[-3:])
        lauf.say("  droport rc=  %s" % re.findall(r"expl: droport rc=(\d+)", t)[-3:])

        # ------------------------------------- 3. auf den Papierkorb
        lauf.image("vor-zug3")
        zug(rel(320, 171), rel(140, 187), "eine Datei -> Papierkorb")
        lauf.image("nach-zug3")
        t = lauf.read_text()
        lauf.say("  droport      %s" % re.findall(r"expl: droport ([^\n]{0,70})", t)[-3:])
        lauf.say("  in den Korb  %s" % re.findall(r"trash rc=(\d+)", t)[-3:])

t = lauf.read_text()
lauf.say("--- Bilanz der Meldungen ---")
for muster, was in ((r"expl: zieh", "Ziehen angefangen"),
                    (r"expl: drop ", "Ablegen Tabelle/Baum"),
                    (r"expl: drop\* rc=(\d+)", "davon vollzogen"),
                    (r"expl: droport", "Ablegen Ortsleiste"),
                    (r"expl: ort nimmt nix", "Ort nimmt nichts"),
                    (r"expl: ort gleich", "schon dort"),
                    (r"trash rc=(\d+)", "in den Papierkorb")):
    r = re.findall(muster, t)
    lauf.say("  %-24s %s" % (was, ("%dx %s" % (len(r), r[:3])) if r else "-"))
lauf.say("== Ende (b) ==")
