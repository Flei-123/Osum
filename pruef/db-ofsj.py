# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-ofsj.py -- GEGENPROBE: stuerzt das System auch OHNE Editor ab?
#
# Beim ersten Versuch, den Editor zu bedienen, ist der Kern mit einem
# `#UD` in `ofsj.enabled`/`ofsj.commit` stehengeblieben -- dem Journal
# des Dateisystems. Bevor irgendetwas am Editor geaendert wird, muss
# geklaert sein, ob das an dieser Runde liegt: `ofsj.fi` ist in ihr nie
# angefasst worden, aber "ich habe es nicht angefasst" ist keine
# Messung.
#
# Also dasselbe noch einmal, nur OHNE `edit`: nur schreiben. Faellt es
# auch dann, liegt es am Schreiben auf die Platte und nicht am Editor.
import time

lauf.say("== GEGENPROBE: schreiben ohne Editor ==")
lauf.m.klick_auf(300, 300)
time.sleep(1)


def command(row, wait=2.5):
    vorher = len(lauf.read_text())
    lauf.m.tippe(row + "\n")
    time.sleep(wait)
    roh = lauf.read_text()[vorher:]
    gut = []
    for z in roh.splitlines():
        z = z.rstrip()
        if not z or z.startswith(("wlib", "wm:", "key:", "explorer:")):
            continue
        gut.append(z)
    return gut


for b in ("echo eins > /data/t1.txt",
          "echo zwei >> /data/t1.txt",
          "cat /data/t1.txt",
          "ls /data"):
    lauf.say("  $ %s" % b)
    for z in command(b):
        lauf.say("      %s" % z[:100])

lauf.image("nach-dem-schreiben")

t = lauf.read_text()
lauf.say("--- Befund ---")
for muster in ("CRASH", "ofsj", "#UD", "kernel halted"):
    lauf.say("  %-16s %dx" % (muster, t.count(muster)))
lauf.say("== Ende Gegenprobe ==")
