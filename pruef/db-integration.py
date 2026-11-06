# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-integration.py -- DIE INTEGRATIONSPRUEFUNG DER BEIDEN RUNDEN.
#
# Die Frage, um die es geht, ist NICHT "laeuft der Dateimanager" und
# auch nicht "laeuft nedit" -- beides ist in der jeweiligen Runde schon
# belegt. Die Frage ist, ob BEIDES GLEICHZEITIG geht, nachdem zwei
# parallel gebaute Zweige konfliktfrei auf main gefallen sind und BEIDE
# kernel/user/wlib.fi angefasst haben.
#
# Warum das eine eigene Pruefung braucht: die beiden Runden haben
# einander in wlib die Zahl 18 doppelt vergeben (K_DROP aus CLIP-2,
# K_TEXTAREA aus GUI-EDITOR). Ein Programm mit Textfeld UND Ablageziel
# ist genau die Mischung, in der so etwas auffliegt -- und die Mischung
# entsteht erst, wenn beide Programme auf DERSELBEN Maschine laufen.
#
# Der Weg:
#   1. Dateimanager aus dem Startmenue, Strg+T -> zwei Reiter
#   2. nedit daneben starten, Text tippen
#   3. Umschalt+Pfeil -- die Auswahl, die es vor dieser Runde nicht gab
#      (kbd.fi::mods_of hat die Umschalttaste ueberhaupt erst auf die
#      Leitung gebracht)
#   4. Bild von beidem nebeneinander
import re
import time

lauf.say("== INTEGRATION: Reiter UND nedit auf EINER Maschine ==")


def window():
    everything = re.findall(
        r"wm: fen i=\d+ id=(\d+) x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+) lay=(\d+)",
        lauf.read_text())
    d = {}
    for f in everything:
        d[int(f[0])] = tuple(int(v) for v in f[1:])
    return d


def reiterstand():
    # Ohne Praefix gesucht: die serielle Leitung traegt mehrere
    # Schreiber und zerschneidet Zeilenanfaenge (siehe db-tabs.py --
    # und siehe der Lauf dieser Runde, in dem k15 mitten in nedits
    # Zeile geschrieben hat).
    r = re.findall(r"reiter (\d+) a=(\d+)", lauf.read_text())
    return r[-1] if r else None


def neditstand():
    r = re.findall(r"reiter (\d+) zeilen (\d+) zeile (\d+) spalte (\d+)",
                   lauf.read_text())
    return r[-1] if r else None


def startmenue_punkt(name):
    """Einen Eintrag im Startmenue anklicken. Gibt True, wenn getroffen."""
    lauf.m.key_press("meta_l")
    time.sleep(3)
    men = [(i, v) for i, v in window().items() if v[4] == 4]
    if not men:
        lauf.say("  KEIN STARTMENUE")
        return False
    mid, (mx, my, mw, mh, _) = men[-1]
    lauf.say("  Startmenue bei (%d,%d) %dx%d" % (mx, my, mw, mh))
    # Das Suchfeld ist die zuverlaessigste Art, ein Programm zu
    # erwischen: tippen und Eingabe. Ein Klick auf eine Zeile haengt an
    # der Zeilenhoehe, und die hat sich in dieser Runde geaendert.
    lauf.m.klick_auf(mx + 207, my + 60)
    time.sleep(1)
    # DAS FELD LEEREN. Beim ersten Anlauf dieser Runde stand danach
    # "DateiEditor+" darin -- das Startmenue behaelt seinen Suchtext
    # ueber das Zuklappen hinweg, und zwei Suchen hintereinander
    # ergeben sonst eine Zeichenkette, die auf nichts passt.
    for _ in range(24):
        lauf.m.key_press("backspace")
    time.sleep(1)
    lauf.m.tippe(name)
    time.sleep(2)
    lauf.m.key_press("ret")
    time.sleep(4)
    return True


# ------------------------------------------------ 1. Der Dateimanager
lauf.say("-- 1. Dateimanager starten --")
vor = set(window().keys())
startmenue_punkt("Datei")
lauf.image("explorer-auf")
renewed = set(window().keys()) - vor
lauf.say("  neue Fenster: %s" % sorted(renewed))
lauf.say("  Reiterstand: %s" % (reiterstand(),))

# ------------------------------------------------ 2. Zweiter Reiter
lauf.say("-- 2. Strg+T: ein zweiter Reiter --")
lauf.m.key_press("ctrl-t")
time.sleep(3)
lauf.image("explorer-zweiter-reiter")
rs = reiterstand()
lauf.say("  Reiterstand nach Strg+T: %s" % (rs,))
if rs and int(rs[0]) >= 2:
    lauf.say("  OK: %s Reiter offen" % rs[0])
else:
    lauf.say("  FEHLT: kein zweiter Reiter")

# ------------------------------------------------ 3. nedit daneben
lauf.say("-- 3. nedit starten, WAEHREND der Explorer offen ist --")
vor2 = set(window().keys())
startmenue_punkt("Editor+")
time.sleep(3)
lauf.image("nedit-auf")
renewed_b = set(window().keys()) - vor2
lauf.say("  neue Fenster: %s" % sorted(renewed_b))
lauf.say("  neditstand: %s" % (neditstand(),))

# ------------------------------------------------ 4. Tippen
lauf.say("-- 4. Text tippen --")
lauf.m.tippe("Integration")
time.sleep(2)
lauf.image("nedit-getippt")
lauf.say("  neditstand nach Tippen: %s" % (neditstand(),))

# ------------------------------------------------ 5. Umschalt-Auswahl
lauf.say("-- 5. Umschalt+Pfeil links: die Auswahl --")
vor_sel = neditstand()
for _ in range(5):
    lauf.m.key_press("shift-left")
    time.sleep(0.3)
time.sleep(2)
lauf.image("nedit-auswahl")
nach_sel = neditstand()
lauf.say("  vor  der Auswahl: %s" % (vor_sel,))
lauf.say("  nach der Auswahl: %s" % (nach_sel,))
if vor_sel and nach_sel and vor_sel[3] != nach_sel[3]:
    lauf.say("  OK: die Marke hat sich bewegt (%s -> %s)"
             % (vor_sel[3], nach_sel[3]))
else:
    lauf.say("  FEHLT: die Marke steht still -- Umschalt kommt nicht an")

# ------------------------------------------------ 6. Beide zusammen
lauf.say("-- 6. Beide Fenster nebeneinander --")
f = window()
lauf.say("  Fenster am Ende: %s" % sorted(f.keys()))
lauf.say("  Reiterstand:  %s" % (reiterstand(),))
lauf.say("  neditstand:   %s" % (neditstand(),))
lauf.image("beide")
lauf.say("== Ende Integration ==")
