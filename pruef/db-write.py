# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-write.py -- DIE ENGE GEGENPROBE zum Absturz.
#
# Befund bis hierher: `echo eins > /data/t1.txt` laeuft durch (rc=0),
# und das darauffolgende `cat /data/t1.txt` bringt den Kern mit
# `STUFE ST 38 MAX 38` zum Stehen -- der Editor war zu diesem Zeitpunkt
# nie gestartet. Der Verdacht ist also: SCHREIBEN auf die RAM-Wurzel
# (`-initrd`, also `modfs`) und danach LESEN.
#
# Dieses Drehbuch macht nur noch das, in kleinsten Schritten, und sagt
# nach jedem, ob die Maschine noch lebt. Damit steht am Ende fest,
# WELCHER Schritt es ist -- und ob es an dieser Runde liegt (sie hat
# weder am Dateisystem noch an der Shell eine Zeile geaendert).
import time

lauf.say("== GEGENPROBE: welcher Schritt bringt den Kern zum Stehen? ==")
lauf.m.klick_auf(300, 300)
time.sleep(1)


def lebt():
    """Laeuft die Maschine noch? Ein Absturz steht auf der Leitung."""
    t = lauf.read_text()
    return ("kernel halted" not in t) and ("crash:  0" not in t)


def schritt(row, wait=3.0):
    if not lebt():
        lauf.say("  (uebersprungen, die Maschine steht schon): %s" % row)
        return
    vorher = len(lauf.read_text())
    lauf.m.tippe(row + "\n")
    time.sleep(wait)
    roh = lauf.read_text()[vorher:]
    reply = []
    for z in roh.splitlines():
        z = z.rstrip()
        if not z or z.startswith(("wlib", "wm:", "key:", "elf:", "osum ",
                                  "taskbar", "explorer:")):
            continue
        reply.append(z[:90])
    lauf.say("  $ %-34s %s" % (row, "LEBT" if lebt() else "*** STEHT ***"))
    for z in reply[:4]:
        lauf.say("      %s" % z)


# Erst LESEN, was schon da ist -- das ruehrt das Journal nicht an.
schritt("ls /data")
schritt("cat /data/alpha.txt")
# Dann SCHREIBEN.
schritt("echo eins > /data/t1.txt")
# Und das Gelesene danach.
schritt("ls /data")
schritt("cat /data/t1.txt")

lauf.image("gegenprobe")
t = lauf.read_text()
lauf.say("--- Befund ---")
for muster in ("kernel halted", "STUFE ST", "ofsj", "#UD", "crash:"):
    lauf.say("  %-16s %dx" % (muster, t.count(muster)))
lauf.say("== Ende ==")
