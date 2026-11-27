#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/batticon/run.sh -- the tray battery as a Windows 11 style horizontal battery picture: proportional fill, green fill + bolt while
# charging, plug while on mains and full, red fill at 20 % or less. Scale 1 and 2, pixel checks per state, counter-proof on the old tree.
#   bash tools/batticon/run.sh [<keep-dir>]      BATTICON_OLD=<ref> (default origin/main), BATTICON_NOCP=1 skips the counter-proof
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
ROOT=$(pwd)
KEEP=${1:-}
D=$(mktemp -d)
trap 'cd "$ROOT"; [ -n "${OLDWT:-}" ] && git worktree remove --force "$OLDWT" >/dev/null 2>&1; rm -rf "$D"' EXIT
pass=0; fail=0
CASES=("a discharging 88 0 87 1" "b charging 88 1 87 1" "c plugged 101 2 100 1" "d low 16 0 15 1" "e charging 88 1 87 2" "f low 16 0 15 2")
for line in "${CASES[@]}"; do
    set -- $line
    ( /root/jarvis/bin/heavy bash tools/trayraster/shot.sh "$D/$1" 1280x800 "${6}" "$3" "$4" > "$D/$1.log" 2>&1 ) &
done
OLDPID=""
if [ -z "${BATTICON_NOCP:-}" ]; then
    REF=${BATTICON_OLD:-origin/main}
    OLDWT="$D/oldwt"
    git worktree add --detach "$OLDWT" "$REF" >/dev/null 2>&1
    mkdir -p "$OLDWT/tools/trayraster"; cp tools/trayraster/shot.sh tools/trayraster/script.txt "$OLDWT/tools/trayraster/"
    ( cd "$OLDWT" && firnenv_prepare_old_tree . >/dev/null 2>&1; /root/jarvis/bin/heavy bash tools/trayraster/shot.sh "$D/old" 1280x800 1 88 1 > "$D/old.log" 2>&1 ) &
fi
wait
for line in "${CASES[@]}"; do
    set -- $line
    echo "== $1. $2, ${5} %, scale ${6}"
    python3 -I tools/batticon/check.py "$D/$1" "$2" "$5" "${6}" | tee "$D/$1.res"
    n=$(grep -c '^  OK' "$D/$1.res"); f=$(grep -c '^  FAIL' "$D/$1.res")
    pass=$((pass+n)); fail=$((fail+f))
    [ -n "$KEEP" ] && { mkdir -p "$KEEP/$1"; cp "$D"/$1/* "$KEEP/$1/" 2>/dev/null; }
done
if [ -z "${BATTICON_NOCP:-}" ]; then
    echo "== counter-proof: $REF must go red on the charging picture"
    python3 -I tools/batticon/check.py "$D/old" charging 87 1 > "$D/old.res" 2>&1
    grep FAIL "$D/old.res" | sed 's/^/  (old) /'
    fo=$(grep -c '^  FAIL' "$D/old.res")
    [ "$fo" -ge 3 ] && { echo "  OK    counter-proof: $REF has $fo red checks"; pass=$((pass+1)); } || { echo "  FAIL  counter-proof stayed green ($fo red)"; fail=$((fail+1)); }
    [ -n "$KEEP" ] && { mkdir -p "$KEEP/old"; cp "$D"/old/* "$KEEP/old/" 2>/dev/null; }
fi
echo
echo "BATTICON: $pass passed, $fail failed"
[ "$fail" = 0 ]
