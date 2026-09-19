# SPDX-License-Identifier: GPL-2.0-only
# pruef/db-schreib.py -- DIE ENGE GEGENPROBE zum Absturz.
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

lauf.sag("== GEGENPROBE: welcher Schritt bringt den Kern zum Stehen? ==")
lauf.m.klick_auf(300, 300)
time.sleep(1)


def lebt():
    """Laeuft die Maschine noch? Ein Absturz steht auf der Leitung."""
    t = lauf.lies()
    return ("kernel halted" not in t) and ("absturz:  0" not in t)


def schritt(zeile, warte=3.0):
    if not lebt():
        lauf.sag("  (uebersprungen, die Maschine steht schon): %s" % zeile)
        return
    vorher = len(lauf.lies())
    lauf.m.tippe(zeile + "\n")
    time.sleep(warte)
    roh = lauf.lies()[vorher:]
    antwort = []
    for z in roh.splitlines():
        z = z.rstrip()
        if not z or z.startswith(("wlib", "wm:", "key:", "elf:", "osum ",
                                  "taskbar", "explorer:")):
            continue
        antwort.append(z[:90])
    lauf.sag("  $ %-34s %s" % (zeile, "LEBT" if lebt() else "*** STEHT ***"))
    for z in antwort[:4]:
        lauf.sag("      %s" % z)


# Erst LESEN, was schon da ist -- das ruehrt das Journal nicht an.
schritt("ls /data")
schritt("cat /data/alpha.txt")
# Dann SCHREIBEN.
schritt("echo eins > /data/t1.txt")
# Und das Gelesene danach.
schritt("ls /data")
schritt("cat /data/t1.txt")

lauf.bild("gegenprobe")
t = lauf.lies()
lauf.sag("--- Befund ---")
for muster in ("kernel halted", "STUFE ST", "ofsj", "#UD", "absturz:"):
    lauf.sag("  %-16s %dx" % (muster, t.count(muster)))
lauf.sag("== Ende ==")
