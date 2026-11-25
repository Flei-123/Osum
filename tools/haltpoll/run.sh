#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
MAX_RATIO=${HALTPOLL_MAX_RATIO:-0.95}
TESTS="vfork_exit_wait thread_create_join"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
bash tools/build-kernel.sh "$W/k.mb" --stufe 0 > "$W/build.log" 2>&1 || { tail -5 "$W/build.log"; exit 1; }
SPEED_SMP=4 bash tools/speedcmp/abwords.sh "$W/k.mb" nohaltpoll "$W/k.mb" "" "$W/ab" "${TESTS// /,}" 5 > "$W/ab.log" 2>&1
for t in $TESTS; do
    ratio=$(awk -v t="$t" '$1 == t { print $NF }' "$W/ab.log")
    if [ -n "$ratio" ] && awk -v r="$ratio" -v m="$MAX_RATIO" 'BEGIN { exit !(r < m) }'; then
        ok "$t: halt polling $ratio x of nohaltpoll (limit $MAX_RATIO)"
    else
        bad "$t: halt polling ${ratio:-no data} x of nohaltpoll (limit $MAX_RATIO)"
    fi
done
printf 'HALTPOLL: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
