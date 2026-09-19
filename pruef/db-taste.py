# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-taste.py -- WELCHE QEMU-TASTE GIBT AUF DIESEM SYSTEM EIN ">"?
#
# Zweimal geraten, zweimal falsch (`less` und `0x56` kamen beide als
# Leerzeichen an). Also nicht ein drittes Mal raten, sondern MESSEN:
# jeden Kandidaten einzeln schicken und auf der seriellen Leitung
# nachlesen, welches Zeichen der Kern daraus gemacht hat -- er schreibt
# jeden Tastendruck als `key: X` mit.
import re
import time

lauf.sag("== WELCHE TASTE GIBT '>' ? ==")
lauf.m.klick_auf(300, 300)
time.sleep(1)

KANDIDATEN = [
    "greater", "shift-greater",
    "less", "shift-less",
    "0x56", "shift-0x56",
    "shift-dot", "shift-comma",
    "backslash", "shift-backslash",
]

for k in KANDIDATEN:
    vorher = len(lauf.lies())
    lauf.m.taste(k)
    time.sleep(0.9)
    neu = lauf.lies()[vorher:]
    # Der Kern schreibt jeden Druck als `key: <zeichen>`.
    treffer = re.findall(r"key: (.{1,12})", neu)
    lauf.sag("  %-16s -> %s" % (k, treffer[:3] if treffer else "NICHTS"))

lauf.bild("tastenprobe")
lauf.sag("== Ende ==")
