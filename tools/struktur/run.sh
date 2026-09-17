#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/struktur/run.sh -- DIE ORDNUNG, NACHGEPRUEFT.
#
# Die Ordnung eines Baums zerfaellt nicht durch eine Entscheidung,
# sondern durch hundert kleine. Dieses Skript ist die Bremse. Es
# prueft ZWEI Dinge, die man auseinanderhalten muss:
#
#   1. DIE ABLAGE  -- liegt jede Datei in dem Verzeichnis, in das sie
#                     laut `ablage.txt` gehoert? (raeumlich)
#   2. DIE RICHTUNG -- ruft jedes Modul nur Module gleicher oder
#                     tieferer Schicht? (logisch, `schichten.txt`)
#
# Die Ablage muss VOLLSTAENDIG stimmen: 0 Abweichungen, sonst rot.
# Bei der Richtung gibt es einen Deckel, weil der Kern heute 47 echte
# Brueche hat -- ein Skript, das "0" verlangt, waere ab der ersten
# Zeile rot und wuerde abgeschaltet statt befolgt.
#
#   bash tools/struktur/run.sh
#
# ============================== DIE GEGENPROBEN ==============================
#
# Ein Pruefskript, das nichts findet und trotzdem "OK" meldet, ist in
# diesem Repo ein Fehler. Also prueft dieses Skript ZUERST SICH SELBST,
# und zwar fuer BEIDE Haelften:
#
#   Abschnitt 3 verschiebt in einer Kopie eine Datei an den falschen
#   Ort -- die Ablagepruefung muss anschlagen.
#   Abschnitt 4 baut in einer Kopie einen Regelbruch ein (ein Treiber
#   importiert die Oberflaeche) -- die Richtungspruefung muss
#   anschlagen.
#
# Schlaegt eine der beiden NICHT an, endet der Lauf mit Code 1 -- auch
# wenn der echte Baum in Ordnung waere.
set -uo pipefail
cd "$(dirname "$0")/../.."

DECKEL=47
FEHLER=0

# ---------------------------------------------------------------- 1. Ablage
echo "== 1. die Ablage: liegt jede Datei an ihrem Platz? =="
A=$(python3 tools/struktur/ablage.py --pruefen 2>&1)
ARC=$?
echo "$A" | head -40
if (( ARC != 0 )); then
    echo "ROT: die Ablage weicht ab."
    FEHLER=1
else
    echo "GRUEN: jede Kerndatei liegt in ihrer Schicht."
fi

# -------------------------------------------------------------- 2. Richtung
echo
echo "== 2. die Aufrufrichtung =="
AUSGABE=$(python3 tools/struktur/erhebung.py --pruefen 2>&1)
echo "$AUSGABE" | head -60
BRUECHE=$(echo "$AUSGABE" | sed -n 's/^Schichtregel: [0-9]* Kanten halten, \([0-9]*\) brechen$/\1/p')
HALTEN=$(echo "$AUSGABE" | sed -n 's/^Schichtregel: \([0-9]*\) Kanten halten.*$/\1/p')
if [[ -z $BRUECHE ]]; then
    echo "FEHLER: die Erhebung hat keine Zahl geliefert"
    exit 1
fi
echo
echo "halten: $HALTEN   brechen: $BRUECHE   Deckel: $DECKEL"
if (( BRUECHE > DECKEL )); then
    echo "ROT: $((BRUECHE - DECKEL)) Bruch/Brueche MEHR als der Deckel erlaubt."
    FEHLER=1
elif (( BRUECHE < DECKEL )); then
    echo "GRUEN -- und besser als der Deckel."
    echo "     Bitte DECKEL in diesem Skript auf $BRUECHE senken."
else
    echo "GRUEN -- genau auf dem Deckel."
fi

# ------------------------------------------------- 3. Gegenprobe der Ablage
echo
echo "== 3. Gegenprobe A: merkt die Ablagepruefung einen falschen Ort? =="
PROBE=$(mktemp -d)
trap 'rm -rf "$PROBE"' EXIT
cp -a kernel "$PROBE/kernel" || exit 1
mkdir -p "$PROBE/tools/struktur"
cp tools/struktur/ablage.py tools/struktur/ablage.txt \
   tools/struktur/erhebung.py tools/struktur/schichten.txt \
   tools/struktur/huelle.py "$PROBE/tools/struktur/" || exit 1

VORHER=$(cd "$PROBE" && python3 tools/struktur/ablage.py --pruefen 2>&1 |
         sed -n 's/^Ablage: [0-9]* Dateien am richtigen Ort, \([0-9]*\) am falschen.*$/\1/p')
# `ahci.fi` gehoert nach drv/blk/ -- wir legen sie zurueck nach oben.
mv "$PROBE/kernel/drv/blk/ahci.fi" "$PROBE/kernel/ahci.fi" 2>/dev/null
NACHHER=$(cd "$PROBE" && python3 tools/struktur/ablage.py --pruefen 2>&1 |
          sed -n 's/^Ablage: [0-9]* Dateien am richtigen Ort, \([0-9]*\) am falschen.*$/\1/p')
echo "ahci.fi kuenstlich nach kernel/ zurueckgelegt: vorher $VORHER, nachher $NACHHER"
if [[ -z $VORHER || -z $NACHHER ]]; then
    echo "ROT: die Gegenprobe konnte nicht messen."
    FEHLER=1
elif (( NACHHER > VORHER )); then
    echo "GRUEN: die Ablagepruefung schlaegt an ($VORHER -> $NACHHER)."
else
    echo "ROT: der falsche Ort wurde NICHT bemerkt."
    FEHLER=1
fi
mv "$PROBE/kernel/ahci.fi" "$PROBE/kernel/drv/blk/ahci.fi" 2>/dev/null

# ----------------------------------------------- 4. Gegenprobe der Richtung
echo
echo "== 4. Gegenprobe B: merkt die Richtungspruefung einen Regelbruch? =="
RVOR=$(cd "$PROBE" && python3 tools/struktur/erhebung.py --pruefen 2>&1 |
       sed -n 's/^Schichtregel: [0-9]* Kanten halten, \([0-9]*\) brechen$/\1/p')
# Ein Plattentreiber (Rang 5) darf das Fenster (Rang 9) nicht kennen.
sed -i '0,/^import /s//import ui.wm\nimport /' "$PROBE/kernel/drv/blk/ahci.fi" || exit 1
RNACH=$(cd "$PROBE" && python3 tools/struktur/erhebung.py --pruefen 2>&1 |
        sed -n 's/^Schichtregel: [0-9]* Kanten halten, \([0-9]*\) brechen$/\1/p')
echo "kuenstlicher Bruch in drv/blk/ahci.fi: vorher $RVOR, nachher $RNACH"
if [[ -z $RVOR || -z $RNACH ]]; then
    echo "ROT: die Gegenprobe konnte nicht messen."
    FEHLER=1
elif (( RNACH > RVOR )); then
    echo "GRUEN: die Richtungspruefung schlaegt an ($RVOR -> $RNACH)."
else
    echo "ROT: der eingebaute Bruch wurde NICHT bemerkt."
    FEHLER=1
fi

echo
if (( FEHLER == 0 )); then
    echo "STRUKTUR OK"
else
    echo "STRUKTUR ROT"
fi
exit $FEHLER
