# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-editor.py -- DREHBUCH (d): der Terminal-Editor.
#
# Der Editor ist KEIN Fensterprogramm (kein `import wlib`, Ausgabe ueber
# VT100-Fluchtfolgen). Er laeuft im Terminalfenster des Schreibtischs,
# und genau dort wird er hier auch bedient und fotografiert -- mit
# denselben Tasten, die ein Mensch druecken wuerde.
#
# Gemessen wird, was Justin verlangt hat und was in einem TERMINAL
# moeglich ist: Reiter fuer mehrere Dateien, Zeilennummern am Rand,
# eine Statuszeile mit Zeile/Spalte/Aenderungsstand.
import re
import time

lauf.sag("== (d) der Terminal-Editor ==")

# Ins Terminal klicken, damit die Tastatur dort ankommt.
lauf.m.klick_auf(300, 300)
time.sleep(1)


def befehl(zeile, warte=3.0):
    vorher = len(lauf.lies())
    lauf.m.tippe(zeile + "\n")
    time.sleep(warte)
    return lauf.lies()[vorher:]


# DIE DATEIEN LIEGEN SCHON IM ABBILD (tools/k15/lokal/build-gross.sh).
# Sie hier mit `echo > datei` anzulegen ist NICHT moeglich: das Zeichen
# `>` kommt ueber den QEMU-Monitor auf dieser Tastatur gar nicht an
# (gemessen, pruef/db-taste.py) -- eine Umlenkung laesst sich nicht
# tippen. tools/k11/run.sh:168 macht es aus demselben Grund genauso.
lauf.sag("--- was im Abbild liegt ---")
for z in befehl("cat /data/t1.txt").splitlines():
    if z.strip() and not z.startswith(("wlib", "wm:", "key:")):
        lauf.sag("    %s" % z[:80])

# ------------------------------------------------------ den Editor starten
lauf.sag("--- edit /data/t1.txt ---")
befehl("edit /data/t1.txt", 4.0)
lauf.bild("01-editor-offen")

t = lauf.lies()
lauf.sag("  'edit: ready': %d" % len(re.findall(r"edit: ready", t)))

lauf.sag("== Ende (d) Grundlinie ==")
