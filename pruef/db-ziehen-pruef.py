# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-ziehen-pruef.py -- DREHBUCH (b) MIT NACHLESEN IM SYSTEM.
#
# WARUM DIESES DREHBUCH EXISTIERT, und das ist der Kern der Sache:
# ein Bild zeigt, dass eine Zeile VERSCHWUNDEN ist. Es zeigt NICHT,
# wohin sie gegangen ist. Eine geloeschte, eine verschobene und eine
# kopierte Datei sehen in der Liste, aus der sie fehlt, gleich aus --
# und genau daran ist der erste Entwurf von RUNDE CLIP-2 gescheitert
# (er kopierte und sah auf dem Bild wie ein Verschieben aus).
#
# DAS ABBILD VOM WIRT ZU LESEN HILFT HIER NICHT. QEMU bekommt die
# Wurzel als `-initrd`, also als RAM-Platte; was das System schreibt,
# steht im Arbeitsspeicher der Maschine und nie in der Datei. GEMESSEN:
# pruef/root.img ist nach einem Lauf mit drei Verschiebungen Oktett fuer
# Oktett dasselbe wie vorher. Also wird IM LAUFENDEN SYSTEM nachgesehen,
# mit `ls` in derselben Shell, die auch ein Mensch benutzen wuerde --
# VORHER und NACHHER, damit der Unterschied die Messung ist.
import re
import time

lauf.sag("== (b) Ziehen und Ablegen, mit Nachlesen ==")


def fenster():
    alle = re.findall(
        r"wm: fen i=\d+ id=(\d+) x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+) lay=(\d+)",
        lauf.lies())
    d = {}
    for f in alle:
        d[int(f[0])] = tuple(int(v) for v in f[1:])
    return d


def befehl(zeile, warte=2.5):
    """Einen Befehl in die Shell tippen und NUR die neue Ausgabe lesen."""
    vorher = len(lauf.lies())
    lauf.m.tippe(zeile + "\n")
    time.sleep(warte)
    roh = lauf.lies()[vorher:]
    # Die serielle Leitung traegt auch die Diagnose von wlib (uitrace).
    # Was hier interessiert, ist die Antwort der Shell.
    gut = []
    for z in roh.splitlines():
        z = z.rstrip()
        if not z:
            continue
        if z.startswith(("wlib", "wm:", "explorer:", "expl:", "osum ",
                         "fuib", "qs:", "taskbar", "desktop")):
            continue
        if "fg=" in z or "px=" in z:
            continue
        gut.append(z)
    return gut


def zeig(titel, befehle):
    lauf.sag("--- %s ---" % titel)
    for b in befehle:
        lauf.sag("  $ %s" % b)
        for z in befehl(b):
            lauf.sag("      %s" % z[:110])


# ================================================ 1. VORHER nachsehen
# Das Terminal steht offen. Hineinklicken, damit die Tastatur dort
# ankommt.
lauf.m.klick_auf(300, 300)
time.sleep(1)
zeig("VORHER", ["ls /data", "ls /data/bilder"])
lauf.bild("vorher-terminal")

# ============================================ 2. Dateimanager starten
vorher_f = set(fenster().keys())
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

    neu = [i for i in fenster().keys() if i not in vorher_f and i != mid]
    if not neu:
        lauf.sag("ABBRUCH: kein Dateimanager")
    else:
        wid = max(neu)
        wx, wy, ww, wh, _ = fenster()[wid]
        lauf.sag("Dateimanager id=%d bei %d,%d %dx%d" % (wid, wx, wy, ww, wh))
        rel = lambda dx, dy: (wx + dx, wy + dy)

        def zug(von, nach, was):
            """Druecken, fahren, loslassen -- mit klick.py's `ziehe`.

            NICHT selbst gebaut: `Maschine.ziehe` schaltet auf die
            RELATIVE Maus um, teilt die Strecke ohne Rest auf und
            laesst die Taste in einem `finally` wieder los -- drei
            Eigenschaften, die dort als Fehler gemessen und behoben
            wurden (RUNDE TUERSCHLOSS).
            """
            lauf.sag("ZUG: %s   %s -> %s" % (was, von, nach))
            lauf.m.ziehe(von[0], von[1], nach[0], nach[1])
            time.sleep(2.5)

        # Tabelle: erste Zeile y=221 (Schirm) = 151 im Fenster, je 20.
        #   Zeile 0 bilder · 1 notizen · 2 alpha · 3 beta · 4 delta ...
        # Ortsleiste: Home y=198 = 128 im Fenster, je 20.
        #   0 Home · 1 Pictures · 2 Start · 3 Trash · 4 Network
        lauf.bild("vor-zug1")
        zug(rel(320, 191), rel(320, 151), "alpha.txt -> Ordner bilder")
        lauf.bild("nach-zug1")

        lauf.bild("vor-zug2")
        zug(rel(320, 191), rel(140, 147), "die naechste Datei -> Ort Pictures")
        lauf.bild("nach-zug2")

        # DER PAPIERKORB. Zeile 3 der Ortsleiste: Home(128) Pictures(148)
        # Start(168) Trash(188) Network(208) -- im Fenster gerechnet.
        #
        # ANGEFASST WIRD EINE ZEILE WEITER UNTEN (zeta.md, Zeile 5),
        # und das ist kein Schoenheitsfehler, sondern noetig: nach zwei
        # Zuegen ist Tabellenzeile 2 auf y=261 gerutscht und der
        # Papierkorb liegt bei y=258 -- drei Bildpunkte Hoehenunterschied.
        # `wlib` meldet `K_DRAG` aber erst, wenn der Zeiger die
        # angefasste ZEILE VERLAESST; ein Zug, der auf derselben Hoehe
        # bleibt, ist fuer die Bibliothek kein Zug. GEMESSEN im Lauf
        # `ziehen3`: kein `expl: zieh` fuer den dritten Zug.
        lauf.bild("vor-zug3")
        zug(rel(320, 251), rel(140, 188), "zeta.md -> Papierkorb")
        lauf.bild("nach-zug3")

        t = lauf.lies()
        lauf.sag("--- was der Dateimanager gemeldet hat ---")
        for m, w in ((r"expl: zieh ([^\n]{0,60})", "angefasst"),
                     (r"expl: drop ([^\n]{0,70})", "auf Tabelle/Baum"),
                     (r"expl: drop\* rc=(\d+)", "  vollzogen rc"),
                     (r"expl: droport ([^\n]{0,70})", "auf Ortsleiste"),
                     (r"expl: droport rc=(\d+)", "  vollzogen rc"),
                     (r"trash rc=(\d+) id=(\d+)", "in den Papierkorb")):
            r = re.findall(m, t)
            lauf.sag("  %-20s %s" % (w, r[-3:] if r else "-"))

# ================================================ 3. NACHHER nachsehen
# Zurueck ins Terminal. Es liegt UNTER dem Dateimanager, also auf eine
# Stelle klicken, die frei ist -- der linke Rand des Terminalfensters.
lauf.m.klick_auf(40, 300)
time.sleep(1.5)
# DER KORB LIEGT AN DER WURZEL DES DATENTRAEGERS. `trash.korb_von`
# ruft `root_from`, und das nimmt die laengste passende EINHAENGESTELLE
# -- `/data` ist keine, also ist die Wurzel `/` und der Korb
# `/.papierkorb`. Unter /data nachzusehen waere die falsche Stelle.
zeig("NACHHER", ["ls /data", "ls /data/bilder",
                 "ls /.papierkorb", "ls /.papierkorb/files"])
lauf.bild("nachher-terminal")
lauf.sag("== Ende (b) ==")
