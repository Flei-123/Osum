#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."

DECKEL=47
FEHLER=0

# ---------------------------------------------------------------- 1. Ablage
echo "== 1. die Ablage: liegt jede Datei an ihrem Platz? =="
A=$(python3 tools/structure/filing.py --pruefen 2>&1)
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

echo
echo "== 3. Gegenprobe A: merkt die Ablagepruefung einen falschen Ort? =="
PROBE=$(mktemp -d)
trap 'rm -rf "$PROBE"' EXIT
cp -a kernel "$PROBE/kernel" || exit 1
mkdir -p "$PROBE/tools/struktur"
cp tools/structure/filing.py tools/structure/filing.txt \
   tools/struktur/erhebung.py tools/struktur/schichten.txt \
   tools/structure/shell.py "$PROBE/tools/struktur/" || exit 1

VORHER=$(cd "$PROBE" && python3 tools/structure/filing.py --pruefen 2>&1 |
         sed -n 's/^Ablage: [0-9]* Dateien am richtigen Ort, \([0-9]*\) am falschen.*$/\1/p')
mv "$PROBE/kernel/drv/blk/ahci.fi" "$PROBE/kernel/ahci.fi" 2>/dev/null
NACHHER=$(cd "$PROBE" && python3 tools/structure/filing.py --pruefen 2>&1 |
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
