#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/trayraster/run.sh -- Windows 11 tray raster: equal cells, one gap, 16 px symbols, one centre line, battery text never
# clipped, program symbols as big as the start logo; several resolutions/scales/percent values + counter-proof on the old tree.
#   bash tools/trayraster/run.sh [<keep-dir>]    TRAYRASTER_OLD=<ref> (default origin/main) is the counter-proof tree
#   TRAYRASTER_NOCP=1 skips the counter-proof, TRAYRASTER_ONLY=<n> runs only matrix line n (1-based).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
KEEP=${1:-}
D=$(mktemp -d); trap 'cd "$ROOT"; [ -n "${OLDWT:-}" ] && git worktree remove --force "$OLDWT" >/dev/null 2>&1; rm -rf "$D"' EXIT
pass=0; fail=0
# res scale demo(=percent+1) charging
MATRIX=("1280x800 1 101 0" "1024x768 1 8 1" "1280x720 1 51 0" "1600x900 1 101 0" "1280x800 2 101 0" "1600x900 2 1 0")
i=0
for line in "${MATRIX[@]}"; do
    i=$((i+1)); [ -n "${TRAYRASTER_ONLY:-}" ] && [ "$TRAYRASTER_ONLY" != "$i" ] && continue
    set -- $line
    echo "== $i. tree: $1 scale $2 battery/volume $(( $3 - 1 )) % charging $4"
    bash tools/trayraster/shot.sh "$D/new$i" "$1" "$2" "$3" "$4" > "$D/new$i.log" 2>&1
    python3 -I tools/trayraster/check.py "$D/new$i" "$2" | tee "$D/new$i.res"
    n=$(grep -c '^  OK' "$D/new$i.res"); f=$(grep -c '^  FAIL' "$D/new$i.res")
    pass=$((pass+n)); fail=$((fail+f))
    [ "$n" -ge 15 ] && { echo "  OK    $n checks ran"; pass=$((pass+1)); } || { echo "  FAIL  only $n checks"; fail=$((fail+1)); }
    if [ -n "$KEEP" ]; then mkdir -p "$KEEP/new$i"; cp "$D"/new$i/* "$KEEP/new$i/"; fi
done
if [ -z "${TRAYRASTER_NOCP:-}" ] && [ -z "${TRAYRASTER_ONLY:-}" ]; then
    echo "== COUNTER-PROOF: the old tree (only the demo keys added) must go red"
    REF=${TRAYRASTER_OLD:-origin/main}
    OLDWT="$D/oldwt"
    git worktree add --detach "$OLDWT" "$REF" >/dev/null 2>&1
    python3 -I tools/trayraster/demo_patch.py "$OLDWT"
    mkdir -p "$OLDWT/tools/trayraster"; cp tools/trayraster/* "$OLDWT/tools/trayraster/"
    (cd "$OLDWT" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1; bash tools/trayraster/shot.sh "$D/old" 1280x800 1 101 0 > "$D/old.log" 2>&1)
    python3 -I tools/trayraster/check.py "$D/old" 1 > "$D/old.res"; grep FAIL "$D/old.res" | sed 's/^/  (old) /'
    fo=$(grep -c '^  FAIL' "$D/old.res")
    [ "$fo" -ge 4 ] && { echo "  OK    counter-proof: $REF has $fo red checks"; pass=$((pass+1)); } || { echo "  FAIL  counter-proof stayed green ($fo red)"; fail=$((fail+1)); }
    if [ -n "$KEEP" ]; then mkdir -p "$KEEP/old"; cp "$D"/old/* "$KEEP/old/"; fi
fi
echo; echo "TRAYRASTER: $pass passed, $fail failed"
[ "$fail" = 0 ]
