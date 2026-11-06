#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."

DECKEL=42
FEHLER=0

# ---------------------------------------------------------------- 1. Ablage
echo "== 1. the filing: is every file in its place? =="
A=$(python3 tools/structure/filing.py --pruefen 2>&1)
ARC=$?
echo "$A" | head -40
if (( ARC != 0 )); then
    echo "RED: the filing deviates."
    FEHLER=1
else
    echo "GREEN: every kernel file is in its layer."
fi

# -------------------------------------------------------------- 2. Richtung
echo
echo "== 2. die Aufrufrichtung =="
AUSGABE=$(python3 tools/struktur/erhebung.py --pruefen 2>&1)
echo "$AUSGABE" | head -60
BRUECHE=$(echo "$AUSGABE" | sed -n 's/^Schichtregel: [0-9]* Kanten halten, \([0-9]*\) brechen$/\1/p')
HALTEN=$(echo "$AUSGABE" | sed -n 's/^Schichtregel: \([0-9]*\) Kanten halten.*$/\1/p')
if [[ -z $BRUECHE ]]; then
    echo "ERROR: the survey delivered no number"
    exit 1
fi
echo
echo "halten: $HALTEN   brechen: $BRUECHE   Deckel: $DECKEL"
if (( BRUECHE > DECKEL )); then
    echo "RED: $((BRUECHE - DECKEL)) break(s) MORE than the cap allows."
    FEHLER=1
elif (( BRUECHE < DECKEL )); then
    echo "GREEN -- and better than the cap."
    echo "     Please lower DECKEL in this script to $BRUECHE."
else
    echo "GREEN -- exactly at the cap."
fi

echo
echo "== 3. control run A: does the filing check notice a wrong place? =="
PROBE=$(mktemp -d)
trap 'rm -rf "$PROBE"' EXIT
cp -a kernel "$PROBE/kernel" || exit 1
mkdir -p "$PROBE/tools/struktur" "$PROBE/tools/structure"
cp tools/struktur/erhebung.py tools/struktur/schichten.txt "$PROBE/tools/struktur/" || exit 1
cp tools/structure/filing.py tools/structure/filing.txt \
   tools/structure/shell.py "$PROBE/tools/structure/" || exit 1

VORHER=$(cd "$PROBE" && python3 tools/structure/filing.py --pruefen 2>&1 |
         sed -n 's/^filing: [0-9]* files in the right place, \([0-9]*\) in the wrong one.*$/\1/p')
mv "$PROBE/kernel/drv/blk/ahci.fi" "$PROBE/kernel/ahci.fi" 2>/dev/null
NACHHER=$(cd "$PROBE" && python3 tools/structure/filing.py --pruefen 2>&1 |
          sed -n 's/^filing: [0-9]* files in the right place, \([0-9]*\) in the wrong one.*$/\1/p')
echo "ahci.fi kuenstlich nach kernel/ zurueckgelegt: vorher $VORHER, nachher $NACHHER"
if [[ -z $VORHER || -z $NACHHER ]]; then
    echo "RED: the control run could not measure."
    FEHLER=1
elif (( NACHHER > VORHER )); then
    echo "GREEN: the filing check fires ($VORHER -> $NACHHER)."
else
    echo "RED: the wrong place was NOT noticed."
    FEHLER=1
fi
mv "$PROBE/kernel/ahci.fi" "$PROBE/kernel/drv/blk/ahci.fi" 2>/dev/null

# ----------------------------------------------- 4. Gegenprobe der Richtung
echo
echo "== 4. control run B: does the direction check notice a rule break? =="
RVOR=$(cd "$PROBE" && python3 tools/struktur/erhebung.py --pruefen 2>&1 |
       sed -n 's/^Schichtregel: [0-9]* Kanten halten, \([0-9]*\) brechen$/\1/p')
sed -i '0,/^import /s//import ui.wm\nimport /' "$PROBE/kernel/drv/blk/ahci.fi" || exit 1
RNACH=$(cd "$PROBE" && python3 tools/struktur/erhebung.py --pruefen 2>&1 |
        sed -n 's/^Schichtregel: [0-9]* Kanten halten, \([0-9]*\) brechen$/\1/p')
echo "kuenstlicher Bruch in drv/blk/ahci.fi: vorher $RVOR, nachher $RNACH"
if [[ -z $RVOR || -z $RNACH ]]; then
    echo "RED: the control run could not measure."
    FEHLER=1
elif (( RNACH > RVOR )); then
    echo "GREEN: the direction check fires ($RVOR -> $RNACH)."
else
    echo "RED: the built-in break was NOT noticed."
    FEHLER=1
fi

echo
if (( FEHLER == 0 )); then
    echo "STRUKTUR OK"
else
    echo "STRUKTUR ROT"
fi
exit $FEHLER
