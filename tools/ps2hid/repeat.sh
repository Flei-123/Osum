#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ps2hid/repeat.sh <n> <outdir> -- runs tools/ps2hid/run.sh n times in a row on ONE kernel build (flake check).
#   /root/jarvis/bin/heavy bash tools/ps2hid/repeat.sh 3 /tmp/ps2rep
# Per run: <outdir>/run<i>.log + serial dumps (PS2_KEEP). Last line: "REPEAT: <ok> of <n> runs fully green".
set -uo pipefail
cd "$(dirname "$0")/../.."
N=${1:?usage: repeat.sh <n> <outdir>}; OUT=${2:?usage: repeat.sh <n> <outdir>}
mkdir -p "$OUT"
export PS2_BUILD="$OUT/build"
good=0
for i in $(seq 1 "$N"); do
    PS2_KEEP="$OUT/run$i" bash tools/ps2hid/run.sh > "$OUT/run$i.log" 2>&1
    line=$(grep -a '^PS2HID:' "$OUT/run$i.log" | tail -1)
    echo "run $i: $line"
    grep -aE 'FAIL' "$OUT/run$i.log" | head -3
    case "$line" in *" 0 failed"*) good=$((good+1)) ;; esac
done
echo "REPEAT: $good of $N runs fully green"
[ "$good" = "$N" ]
