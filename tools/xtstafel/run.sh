#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/xtstafel/run.sh -- DIE ABNAHME VON K-022: DIE SCHLUESSELTAFEL.
#
# K-022: der XTS-Schluesselspeicher hielt genau EINEN Schluessel. Ein
# zweiter verschluesselter Traeger fuellte ihn bei jedem Wechsel neu,
# rund 12 us je Wechsel. Diese Runde hat daraus eine Tafel mit vier
# Plaetzen gemacht.
#
# WAS HIER GEMESSEN WIRD, und jedes Stueck mit seiner Gegenprobe:
#
#   1. DER WECHSEL. Zwei Traeger abwechselnd, 200 Sektoren. Nach dem
#      Aufwaermen darf die Zahl der Fuellungen NICHT mehr steigen.
#      GEGENPROBE: dieselbe Messung mit SLOTS=1 -- das ist der Zustand
#      VOR dieser Runde, und er MUSS durchfallen (200 Fuellungen).
#   2. `forget()` LOESCHT ALLE PLAETZE. Nachgesehen wird im echten
#      Speicher der Tafel, nicht in einer Behauptung -- das ist die
#      Frage, die Runde AESNI ausdruecklich offen gelassen hat.
#      GEGENPROBE: ein `forget()`, das nur Platz 0 raeumt, MUSS
#      durchfallen.
#   3. Und die drei Nachbarabnahmen bleiben gruen (61/0, 31/0, 35/0) --
#      das laeuft NICHT hier, sondern in den eigenen Laeufern; hier
#      steht nur, dass es dazugehoert.
#
# Aufruf:  bash tools/xtstafel/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"; cp -f "$TMPD.xts" lib/crypto/xts.fi 2>/dev/null || true' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

echo "== 1. die Tafel: Wechsel ohne Neufuellen =="
if $FIRNC tools/xtstafel/tafel.fi -o "$TMPD/tafel" 2>"$TMPD/t.err"; then
    ok "tools/xtstafel/tafel.fi uebersetzt"
else
    bad "tafel.fi laesst sich nicht uebersetzen"
    sed 's/^/        /' "$TMPD/t.err" | head -20
    echo "XTSTAFEL: $pass bestanden, $fail gescheitert"; exit 1
fi
"$TMPD/tafel" > "$TMPD/tafel.txt" 2>&1
rc=$?
sed 's/^/        /' "$TMPD/tafel.txt"
if [ "$rc" = 0 ]; then
    ok "die Tafel-Abnahme ist gruen (fehler=0)"
else
    bad "die Tafel-Abnahme ist durchgefallen"
fi
W=$(grep -oE '200 Sektoren abwechselnd, Fuellungen: [0-9]+' "$TMPD/tafel.txt" | grep -oE '[0-9]+$')
if [ "${W:-x}" = 0 ]; then
    ok "KEIN Neufuellen beim Wechsel zwischen zwei Traegern (Fuellungen=0)"
else
    bad "beim Wechsel wird neu gefuellt (Fuellungen=${W:-?})"
fi

echo "== 2. der Loeschtest: nach forget() steht nichts mehr da =="
if $FIRNC tools/xtstafel/loeschen.fi -o "$TMPD/loeschen" 2>"$TMPD/l.err"; then
    "$TMPD/loeschen" > "$TMPD/loeschen.txt" 2>&1
    rc=$?
    sed 's/^/        /' "$TMPD/loeschen.txt"
    if [ "$rc" = 0 ]; then
        ok "nach forget() ist die ganze Tafel genullt"
    else
        bad "nach forget() steht noch etwas in der Tafel"
    fi
else
    bad "loeschen.fi laesst sich nicht uebersetzen"
    sed 's/^/        /' "$TMPD/l.err" | head -20
fi

# ==================================================================
# DIE GEGENPROBEN. Beide aendern lib/crypto/xts.fi, messen und legen
# die Datei DANACH WIEDER HIN. Ohne sie waere jede Zahl oben eine
# Behauptung: eine Abnahme, die auch am kaputten Zustand gruen wird,
# misst nichts.
# ==================================================================
cp -f lib/crypto/xts.fi "$TMPD.xts"

echo "== 3. GEGENPROBE: ein Platz (der Zustand VOR dieser Runde) =="
sed -i 's/^const SLOTS: usize = 4$/const SLOTS: usize = 1/' lib/crypto/xts.fi
if $FIRNC tools/xtstafel/tafel.fi -o "$TMPD/g1" 2>/dev/null; then
    "$TMPD/g1" > "$TMPD/g1.txt" 2>&1
    G=$(grep -oE '200 Sektoren abwechselnd, Fuellungen: [0-9]+' "$TMPD/g1.txt" | grep -oE '[0-9]+$')
    if [ "${G:-0}" -gt 0 ]; then
        ok "mit EINEM Platz wird bei jedem Wechsel neu gefuellt (Fuellungen=$G) -- die Messung greift"
    else
        bad "auch mit einem Platz keine Fuellung -- dann misst die Abnahme nichts"
    fi
else
    bad "die Gegenprobe laesst sich nicht uebersetzen"
fi
cp -f "$TMPD.xts" lib/crypto/xts.fi

echo "== 4. GEGENPROBE: forget() raeumt nur EINEN Platz =="
python3 - <<'PYEOF'
p="lib/crypto/xts.fi"
s=open(p,encoding="utf-8").read()
s=s.replace("""fn forget() {
    var s: usize = 0
    while s < SLOTS {""","""fn forget() {
    var s: usize = 0
    while s < 1 {""",1)
open(p,"w",encoding="utf-8").write(s)
PYEOF
if $FIRNC tools/xtstafel/loeschen.fi -o "$TMPD/g2" 2>/dev/null; then
    "$TMPD/g2" > "$TMPD/g2.txt" 2>&1
    if [ $? != 0 ]; then
        R=$(grep -oE 'Oktette ungleich 0 nach forget\(\): [0-9]+' "$TMPD/g2.txt" | grep -oE '[0-9]+$')
        ok "ein halbes forget() wird ERWISCHT (Rest: ${R:-?} Oktette) -- der Loeschtest greift"
    else
        bad "ein halbes forget() kommt durch -- der Loeschtest taugt nicht"
    fi
else
    bad "die Gegenprobe laesst sich nicht uebersetzen"
fi
cp -f "$TMPD.xts" lib/crypto/xts.fi

echo "XTSTAFEL: $pass bestanden, $fail gescheitert"
[ "$fail" = 0 ] || exit 1
