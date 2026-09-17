#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/struktur/run.sh -- DIE SCHICHTREGEL, NACHGEPRUEFT.
#
# Die Ordnung eines Baums zerfaellt nicht durch eine Entscheidung,
# sondern durch hundert kleine. Dieses Skript ist die Bremse: es zaehlt
# die Kanten, die die Schichtregel brechen, und endet mit Code 1,
# sobald es MEHR werden als der festgehaltene Stand.
#
#   bash tools/struktur/run.sh
#
# WARUM EIN DECKEL UND KEINE NULL: der Kern hat heute 47 Brueche
# (gemessen, siehe docs/STRUKTUR.md). Ein Skript, das "0 Brueche"
# verlangt, waere ab der ersten Zeile rot und damit wertlos -- es
# wuerde abgeschaltet statt befolgt. Der Deckel steht in DECKEL, faellt
# mit jeder aufgeraeumten Kante und darf NIE steigen.
#
# ============================== DIE GEGENPROBE ==============================
#
# Ein Pruefskript, das nichts findet und trotzdem "OK" meldet, ist in
# diesem Repo ein Fehler. Also prueft dieses Skript ZUERST SICH SELBST:
# Abschnitt 2 stellt einen Regelbruch KUENSTLICH her (ein Treiber
# bekommt ein `import` der Oberflaeche, in einer Kopie des Baums) und
# verlangt, dass die Pruefung anschlaegt. Tut sie es nicht, endet der
# Lauf mit Code 1 -- auch wenn der echte Baum in Ordnung waere.
set -uo pipefail
cd "$(dirname "$0")/../.."

DECKEL=47
FEHLER=0

echo "== 1. der Baum =="
AUSGABE=$(python3 tools/struktur/erhebung.py --pruefen 2>&1)
RC=$?
echo "$AUSGABE" | head -60
BRUECHE=$(echo "$AUSGABE" | sed -n 's/^Schichtregel: [0-9]* Kanten halten, \([0-9]*\) brechen$/\1/p')
HALTEN=$(echo "$AUSGABE" | sed -n 's/^Schichtregel: \([0-9]*\) Kanten halten.*$/\1/p')

if [[ -z $BRUECHE ]]; then
    echo "FEHLER: die Erhebung hat keine Zahl geliefert (Code $RC)"
    exit 1
fi

echo
echo "halten: $HALTEN   brechen: $BRUECHE   Deckel: $DECKEL"
if (( BRUECHE > DECKEL )); then
    echo "ROT: $((BRUECHE - DECKEL)) Bruch/Brueche MEHR als der Deckel erlaubt."
    echo "     Entweder die neue Kante entfernen oder die Datei in die"
    echo "     richtige Schicht setzen (tools/struktur/schichten.txt)."
    FEHLER=1
elif (( BRUECHE < DECKEL )); then
    echo "GRUEN -- und besser als der Deckel."
    echo "     Bitte DECKEL in diesem Skript auf $BRUECHE senken,"
    echo "     damit der Fortschritt nicht wieder verlorengeht."
else
    echo "GRUEN -- genau auf dem Deckel."
fi

echo
echo "== 2. die Gegenprobe: schlaegt die Pruefung ueberhaupt an? =="
# Ein Treiber (dev, Rang 5), der die Oberflaeche (ui, Rang 9) ruft, ist
# per Regel ein Bruch. Wir bauen ihn in einer KOPIE und lassen dieselbe
# Pruefung darauf los.
PROBE=$(mktemp -d)
trap 'rm -rf "$PROBE"' EXIT
cp -a kernel "$PROBE/kernel" || exit 1
mkdir -p "$PROBE/tools/struktur"
cp tools/struktur/erhebung.py tools/struktur/schichten.txt "$PROBE/tools/struktur/" || exit 1

VORHER=$(cd "$PROBE" && python3 tools/struktur/erhebung.py --pruefen 2>&1 |
         sed -n 's/^Schichtregel: [0-9]* Kanten halten, \([0-9]*\) brechen$/\1/p')

# `ahci` ist ein Plattentreiber und darf `wm` (das Fenster) nicht kennen.
sed -i '0,/^import /s//import wm\nimport /' "$PROBE/kernel/ahci.fi" || exit 1

NACHHER=$(cd "$PROBE" && python3 tools/struktur/erhebung.py --pruefen 2>&1 |
          sed -n 's/^Schichtregel: [0-9]* Kanten halten, \([0-9]*\) brechen$/\1/p')

echo "kuenstlicher Bruch in kernel/ahci.fi:  vorher $VORHER, nachher $NACHHER"
if [[ -z $VORHER || -z $NACHHER ]]; then
    echo "ROT: die Gegenprobe konnte nicht messen."
    FEHLER=1
elif (( NACHHER > VORHER )); then
    echo "GRUEN: die Pruefung schlaegt an ($VORHER -> $NACHHER)."
else
    echo "ROT: der eingebaute Bruch wurde NICHT bemerkt."
    echo "     Damit ist dieses Skript wertlos, nicht der Baum in Ordnung."
    FEHLER=1
fi

echo
if (( FEHLER == 0 )); then
    echo "STRUKTUR OK"
else
    echo "STRUKTUR ROT"
fi
exit $FEHLER
