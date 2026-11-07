#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/summary.sh; summary_begin AAC
D=$(mktemp -d)
trap 'summary_guard; rm -rf "$D"; summary_exit_status || exit 1' EXIT
trap 'exit 1' HUP INT TERM
for w in ffmpeg python3; do
    command -v "$w" >/dev/null 2>&1 || { summary_note "skipped, $w is missing"; exit 0; }
done
python3 -I -c 'import numpy' 2>/dev/null || { summary_note "skipped, numpy is missing"; exit 0; }
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$(pwd)/lib"
[ -x "$FIRNC" ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
pass=0; fail=0
"$FIRNC" --profile=app -o "$D/aacdec" tools/aac/aacdec.fi > "$D/build.log" 2>&1 \
    || { grep -v RWX "$D/build.log" | head -5; summary_emit 0 1 0; exit 1; }
bash tools/aac/mkclips.sh "$D/c" || { echo "  FAIL  clips"; summary_emit 0 1 0; exit 1; }
tally() {
    while IFS= read -r line; do
        echo "$line"
        case "$line" in *"  OK "*|"  OK "*) pass=$((pass+1));; *FAIL*) fail=$((fail+1));; esac
    done
}
check() {
    local name=$1 channels=$2 mode=${3:-} src=${4:-$1} ref=${5:-$1}
    "$D/aacdec" "$D/c/$src.aac" "$D/c/$name.out" > "$D/c/$name.rep"
    local bad
    bad=$(sed -n 's/.* BAD \([0-9]*\)$/\1/p' "$D/c/$name.rep")
    python3 -I tools/aac/compare.py "$D/c/$name.out" "$D/c/$ref.ref" "$channels" "$name" $mode > "$D/line.txt"
    tally < "$D/line.txt"
    if [ -z "$mode" ]; then
        if [ "${bad:-1}" = 0 ]; then echo "  OK    $name: no undecodable frame"; pass=$((pass+1)); else echo "  FAIL  $name: $bad undecodable frames"; fail=$((fail+1)); fi
    fi
}
while read -r name rate channels; do
    check "$name" "$channels"
done < "$D/c/list.txt"
python3 -I - "$D/c/tone_st.aac" "$D/c/broken.aac" <<'PY'
import sys
data = bytearray(open(sys.argv[1], "rb").read())
for i in range(2000, len(data), 97):
    data[i] ^= 0x5A
open(sys.argv[2], "wb").write(data)
PY
check broken_counter 2 expect-fail broken tone_st
python3 -I - "$D/c/tone_st.ref" "$D/c/shifted.ref" <<'PY'
import sys
data = open(sys.argv[1], "rb").read()
open(sys.argv[2], "wb").write(data[400:])
PY
"$D/aacdec" "$D/c/tone_st.aac" "$D/c/shift.out" > /dev/null
python3 -I tools/aac/compare.py "$D/c/shift.out" "$D/c/shifted.ref" 2 shifted_counter expect-fail > "$D/line.txt"
tally < "$D/line.txt"
summary_emit "$pass" "$fail" 18
