#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# pruef/beide.sh -- der Durchgang bei BEIDEN Aufloesungen, nacheinander.
#
# Nacheinander und nicht gleichzeitig: zwei Durchgaenge sind zwei QEMUs
# mit je 2 GiB, dazu die Bildsuche, und auf dieser Platte laeuft
# regelmaessig noch ein zweiter Pruefstand. Gemessen: bei zwei
# gleichzeitigen Laeufen stieg die Last auf 8,7 und die Suche nach EINEM
# Wort in einem 1920x1080-Bild dauerte ueber eine Minute.
#
# Das Skript liegt im Baum und nicht in /tmp: ein Skript in /tmp ist
# nach dem naechsten Aufraeumen weg, und dann startet der Lauf nicht --
# genau das ist in dieser Runde zweimal passiert.
set -uo pipefail
cd "$(dirname "$0")"

python3 durchklick3.py dk1280 1280 800  > /tmp/ts-d1280.log 2>&1
echo "1280x800 fertig"
python3 durchklick3.py dk1920 1920 1080 > /tmp/ts-d1920.log 2>&1
echo "1920x1080 fertig"
