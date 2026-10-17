#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/traylayout/run.sh -- r1015 tray layout (Win11) + r1016 icons without a tile, pictures + counter-proof.
#   bash tools/traylayout/run.sh [<keep-dir>]       TRAYLAYOUT_OLD=<ref> (default bb6511fe) is the counter-proof tree
#   TRAYLAYOUT_NOCP=1 skips the counter-proof run.  Pictures: <keep-dir>/new, <keep-dir>/old.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
KEEP=${1:-}
D=$(mktemp -d); trap 'cd "$ROOT"; [ -n "${OLDWT:-}" ] && git worktree remove --force "$OLDWT" >/dev/null 2>&1; rm -rf "$D"' EXIT
pass=0; fail=0
echo "== 1. the tree (1280x800, keys of the image)"
bash tools/traylayout/shot.sh "$D/new" light > "$D/new.log" 2>&1
python3 -I tools/traylayout/check.py "$D/new" | tee "$D/new.res"
n=$(grep -c '^  OK' "$D/new.res"); f=$(grep -c '^  FAIL' "$D/new.res")
pass=$((pass+n)); fail=$((fail+f))
[ "$n" -ge 10 ] && { echo "  OK    $n checks ran"; pass=$((pass+1)); } || { echo "  FAIL  only $n checks"; fail=$((fail+1)); }
if [ -n "$KEEP" ]; then mkdir -p "$KEEP/new"; cp "$D"/new/* "$KEEP/new/"; fi
if [ -z "${TRAYLAYOUT_NOCP:-}" ]; then
    echo "== 2. COUNTER-PROOF: the old tree must go red"
    REF=${TRAYLAYOUT_OLD:-bb6511fe}
    OLDWT="$D/oldwt"
    git worktree add --detach "$OLDWT" "$REF" >/dev/null 2>&1
    mkdir -p "$OLDWT/tools/traylayout"; cp tools/traylayout/* "$OLDWT/tools/traylayout/"
    (cd "$OLDWT" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1; bash tools/traylayout/shot.sh "$D/old" light > "$D/old.log" 2>&1)
    python3 -I tools/traylayout/check.py "$D/old" > "$D/old.res"; cat "$D/old.res" | grep FAIL | sed 's/^/  (old) /'
    fo=$(grep -c '^  FAIL' "$D/old.res")
    need=4; [ -n "${TRAYLAYOUT_OLD:-}" ] && need=1   # an explicit near ref differs by one change (Z9: volume field)
    [ "$fo" -ge "$need" ] && { echo "  OK    counter-proof: $REF has $fo red checks"; pass=$((pass+1)); } || { echo "  FAIL  counter-proof stayed green ($fo red)"; fail=$((fail+1)); }
    if [ -n "$KEEP" ]; then mkdir -p "$KEEP/old"; cp "$D"/old/* "$KEEP/old/"; fi
fi
echo; echo "TRAYLAYOUT: $pass passed, $fail failed"
[ "$fail" = 0 ]
