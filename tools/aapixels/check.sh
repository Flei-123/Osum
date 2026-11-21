#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
DIR=${1:?usage: check.sh <dir with *.ppm pictures>}
GATE_SHARE=${AAPIX_GATE_SHARE:-0.14}
GATE_HARD=${AAPIX_GATE_HARD:-0.05}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
for f in "$DIR"/*.ppm; do
    line=$(python3 -I tools/aapixels/measure.py "$f")
    share=$(sed -E 's/.*dense_share=([0-9.]+).*/\1/' <<<"$line")
    if awk -v s="$share" -v g="$GATE_SHARE" 'BEGIN{exit !(s>=g)}'; then ok "$(basename "$f") dense_share=$share >= $GATE_SHARE"; else bad "$(basename "$f") dense_share=$share < $GATE_SHARE"; fi
done
first=$(ls "$DIR"/*.ppm | head -1)
hline=$(python3 -I tools/aapixels/measure.py --binarize "$first")
hshare=$(sed -E 's/.*dense_share=([0-9.]+).*/\1/' <<<"$hline")
if awk -v s="$hshare" -v g="$GATE_HARD" 'BEGIN{exit !(s<=g)}'; then ok "counter-proof hardened edges: dense_share=$hshare <= $GATE_HARD"; else bad "counter-proof hardened edges: dense_share=$hshare > $GATE_HARD"; fi
echo "AAPIXELS: $pass passed, $fail failed"
[ "$fail" = 0 ]
