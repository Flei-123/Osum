# SPDX-License-Identifier: GPL-2.0-only
# tools/ota/wait_brand.py -- WANN DER STECKER GEZOGEN WIRD, ENTSCHEIDET
# NICHT DIE UHR, SONDERN DIE MASCHINE SELBST.
#
# WARUM. Der erste Anlauf von Test (e) hat den Zeitpunkt jedes Schusses
# aus einem einzelnen Messlauf hochgerechnet ("21,2 Sekunden bis bereit,
# also schiesse ich bei 21,5"). Auf einem belasteten Wirt braucht
# derselbe Lauf aber leicht das Doppelte -- gemessen: ein Schuss bei
# 27,2 s traf die Maschine, als `ota einspielen` gerade erst anlief.
# Ergebnis waren dreissig makellose "alt" und kein einziges "neu": ein
# Abschnitt, der nur belegt, dass eine Maschine ohne Update unveraendert
# bleibt. Wertlos.
#
# Also liest dieses Skript die serielle Ausgabe MIT, wartet auf eine
# MARKE, die die Maschine selbst gedruckt hat, und kehrt dann nach einem
# Versatz zurueck. Danach zieht run.sh den Stecker. Das trifft die Phase
# unabhaengig davon, wie schnell der Wirt gerade ist.
#
#   wait_brand.py <datei> <marke> <versatz_ms> <frist_s>
#
# Rueckgabe 0: Marke gesehen, Versatz abgewartet.
# Rueckgabe 3: Frist abgelaufen, ohne die Marke zu sehen -- der Aufrufer
#              schiesst trotzdem, muss den Schuss aber als "nicht in der
#              gemeinten Phase" werten. Es wird NICHTS beschoenigt.
import os, sys, time

datei, marke = sys.argv[1], sys.argv[2]
versatz = int(sys.argv[3]) / 1000.0
frist = float(sys.argv[4])
mb = marke.encode()
ende = time.time() + frist
pos = 0
gesehen = False
while time.time() < ende:
    try:
        with open(datei, "rb") as f:
            f.seek(0)
            inhalt = f.read()
    except OSError:
        inhalt = b""
    if mb in inhalt:
        gesehen = True
        break
    time.sleep(0.02)
if not gesehen:
    sys.exit(3)
time.sleep(versatz)
sys.exit(0)
