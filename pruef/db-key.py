# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-key.py -- WELCHE QEMU-TASTE GIBT AUF DIESEM SYSTEM EIN ">"?
#
# Zweimal geraten, zweimal falsch (`less` und `0x56` kamen beide als
# Leerzeichen an). Also nicht ein drittes Mal raten, sondern MESSEN:
# jeden Kandidaten einzeln schicken und auf der seriellen Leitung
# nachlesen, welches Zeichen der Kern daraus gemacht hat -- er schreibt
# jeden Tastendruck als `key: X` mit.
import re
import time

lauf.say("== WELCHE TASTE GIBT '>' ? ==")
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
    vorher = len(lauf.read_text())
    lauf.m.key_press(k)
    time.sleep(0.9)
    renewed = lauf.read_text()[vorher:]
    # Der Kern schreibt jeden Druck als `key: <zeichen>`.
    treffer = re.findall(r"key: (.{1,12})", renewed)
    lauf.say("  %-16s -> %s" % (k, treffer[:3] if treffer else "NICHTS"))

lauf.image("tastenprobe")
lauf.say("== Ende ==")
