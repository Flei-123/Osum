#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. "$ROOT/tools/lib/firnenv.sh"
FC=$FIRNC
OUT=${1:-/tmp/w2f-pruefung}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/lock.sh" && osum_sperre "$OUT"   # A-024
mkdir -p "$OUT"

DEUTER="$OUT/deuter"
if [ ! -x "$DEUTER" ]; then
    "$FC" --profile=app --no-pass=inline -o "$DEUTER" kernel/app/wasm.fi 2>&1 | grep -v 'LOAD segment' || true
fi

gut=0; schlecht=0
for wat in tools/wasm2firn/pruefung/*.wat; do
    name=$(basename "$wat" .wat)
    wat2wasm "$wat" -o "$OUT/$name.wasm" || { echo "  wat2wasm $name fehlgeschlagen"; continue; }
    a=$(timeout 30 "$DEUTER" "$OUT/$name.wasm" 2>&1)
    python3 tools/wasm2firn/wasm2firn.py "$OUT/$name.wasm" -o "$OUT/$name.fi" \
        --wasm-fi kernel/app/wasm.fi --laufzeit tools/wasm2firn/laufzeit.fi.in 2>/dev/null
    "$FC" --profile=app --no-pass=inline -o "$OUT/$name" "$OUT/$name.fi" 2>&1 | grep -v 'LOAD segment' || true
    b=$(timeout 30 "$OUT/$name" 2>&1)
    if [ "$a" = "$b" ] && ! echo "$b" | grep -q FEHLER; then
        n=$(echo "$b" | grep -c OK)
        echo "  OK    $name ($n cases, interpreter and AOT equal)"
        gut=$((gut+1))
    else
        echo "  FEHLER $name"
        echo "    Deuter: $a"
        echo "    AOT   : $b"
        schlecht=$((schlecht+1))
    fi
done
echo
echo "PRUEFUNG: $gut bestanden, $schlecht fehlgeschlagen"
[ "$schlecht" -eq 0 ]
