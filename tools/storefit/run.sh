#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-$(mktemp -d)}
mkdir -p "$OUT"
CONFIGS=${STOREFIT_CONFIGS:-"1920x1080:1:1600x900 1280x800:2:1200x700 1920x1080:1:700x450"}
fail=0
for cfg in $CONFIGS; do
    IFS=: read -r res scale size <<< "$cfg"
    echo "== $res scale $scale window $size =="
    STORE_FAST=1 STORE_PART=window STORE_FIT="$size" STORE_RES="$res" STORE_SCALE="$scale" STORE_SHOTS="$OUT" \
        /root/jarvis/bin/heavy bash tools/store/run.sh > "$OUT/run-$res-$scale-$size.log" 2>&1
    grep -a "FAIL\|STORE:" "$OUT/run-$res-$scale-$size.log" | head -8
    grep -aq "STORE: .* 0 failed" "$OUT/run-$res-$scale-$size.log" || fail=1
done
echo "pictures: $OUT"
[ "$fail" = 0 ]
