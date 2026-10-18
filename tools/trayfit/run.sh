#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/trayfit/run.sh -- the right end of the task bar like Windows 11: language code on ONE line, clock = time over date
# in a cell measured from its text (never cut, also at scale 2, 12 h, long date, English), equal cells and gaps, NO chip
# behind the symbols (only a hover plate).  Pictures (QEMU screendump) + serial, judged by check.py; counter-proof: the
# old tree (TRAYFIT_OLD=<ref>, default origin/main~0 before this round = b46b96d4) must go red.
#   bash tools/trayfit/run.sh [<keep-dir>]    TRAYFIT_NOCP=1 skips the counter-proof, TRAYFIT_ONLY=<n> one matrix line
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
KEEP=${1:-}
D=$(mktemp -d); trap 'cd "$ROOT"; [ -n "${OLDWT:-}" ] && git worktree remove --force "$OLDWT" >/dev/null 2>&1; rm -rf "$D"' EXIT
pass=0; fail=0
# res scale lang flags extra(taskbar.conf keys)
MATRIX=("1280x800|1|de|-|" "1024x768|2|de|wday|clock_weekday=1" "1024x768|1|en|12h|clock_12h=1")
i=0
for line in "${MATRIX[@]}"; do
    i=$((i+1)); [ -n "${TRAYFIT_ONLY:-}" ] && [ "$TRAYFIT_ONLY" != "$i" ] && continue
    IFS='|' read -r res sc lg fl ex <<< "$line"
    echo "== $i. tree: $res scale $sc lang $lg flags $fl"
    bash tools/trayfit/shot.sh "$D/new$i" "$res" "$sc" "$lg" "$ex" > "$D/new$i.log" 2>&1
    python3 -I tools/trayfit/check.py "$D/new$i" "$sc" "$lg" "$fl" | tee "$D/new$i.res"
    n=$(grep -c '^  OK' "$D/new$i.res"); f=$(grep -c '^  FAIL' "$D/new$i.res")
    pass=$((pass+n)); fail=$((fail+f))
    [ "$n" -ge 15 ] && { echo "  OK    $n checks ran"; pass=$((pass+1)); } || { echo "  FAIL  only $n checks"; fail=$((fail+1)); }
    if [ -n "$KEEP" ]; then mkdir -p "$KEEP/new$i"; cp "$D"/new$i/* "$KEEP/new$i/"; fi
done
if [ -z "${TRAYFIT_NOCP:-}" ] && [ -z "${TRAYFIT_ONLY:-}" ]; then
    echo "== COUNTER-PROOF: the old tree must go red"
    REF=${TRAYFIT_OLD:-b46b96d4}
    OLDWT="$D/oldwt"
    git worktree add --detach "$OLDWT" "$REF" >/dev/null 2>&1
    mkdir -p "$OLDWT/tools/trayfit"; cp tools/trayfit/* "$OLDWT/tools/trayfit/"
    (cd "$OLDWT" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1; bash tools/trayfit/shot.sh "$D/old" 1280x800 1 de "" > "$D/old.log" 2>&1)
    python3 -I tools/trayfit/check.py "$D/old" 1 de "-" > "$D/old.res"; grep FAIL "$D/old.res" | sed 's/^/  (old) /'
    fo=$(grep -c '^  FAIL' "$D/old.res")
    [ "$fo" -ge 4 ] && { echo "  OK    counter-proof: $REF has $fo red checks"; pass=$((pass+1)); } || { echo "  FAIL  counter-proof stayed green ($fo red)"; fail=$((fail+1)); }
    if [ -n "$KEEP" ]; then mkdir -p "$KEEP/old"; cp "$D"/old/* "$KEEP/old/"; fi
fi
echo; echo "TRAYFIT: $pass passed, $fail failed"
[ "$fail" = 0 ]
