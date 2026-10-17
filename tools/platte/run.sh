#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/platte/run.sh -- r1062 gate: the text plate follows the ink (wlibc.platte_ink).
# Same settings window at window_alpha=20 and 100 (themestore build.sh, wallpaper=hell). Label pixels within 2 px of ink must be equal
# in both (opaque halo); the ground inside the label rect must differ (mixed with the backdrop). COUNTER-PROOF: the tree one commit
# before (BASE=<rev>, default HEAD~1, full-rectangle plate) must show (almost) no differing ground.
# Usage: [BASE=<rev>] /root/jarvis/bin/heavy bash tools/platte/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
T=$(mktemp -d)
BT=$T/base
cleanup() { git worktree remove --force "$BT" >/dev/null 2>&1; rm -rf "$T"; }
trap cleanup EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { if [ -z "${2:-}" ]; then bad "$1: no number"; return; fi
    if [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"; else bad "$1: $2, expected $3 $4"; fi; }
field() { printf '%s' "$1" | grep -oE "$2=[0-9]+" | head -1 | cut -d= -f2; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { echo "fetch-firnc failed"; exit 1; }
git worktree add --detach "$BT" "${BASE:-HEAD~1}" >/dev/null 2>&1 || { echo "base worktree failed"; exit 1; }
( cd "$BT" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 )
common=(extra=einst wallpaper=hell uitrace=yes keep=yes)
bash tools/themestore/build.sh "$T/full" "${common[@]}" winalpha=100 >"$T/full.log" 2>&1
bash tools/themestore/build.sh "$T/low" "${common[@]}" winalpha=20 >"$T/low.log" 2>&1
( cd "$BT" && bash tools/themestore/build.sh "$T/blow" "${common[@]}" winalpha=20 >"$T/blow.log" 2>&1 )
for d in full low blow; do [ -f "$T/$d/desktop.png" ] && ok "$d: picture taken" || bad "$d: no picture"; done
N=$(python3 -I tools/platte/check.py "$T/low/desktop.png" "$T/low/serial.txt" "$T/full/desktop.png")
O=$(python3 -I tools/platte/check.py "$T/blow/desktop.png" "$T/blow/serial.txt" "$T/full/desktop.png")
echo "  new : $N"; echo "  base: $O"
num "labels measured" "$(field "$N" labels)" ge 10
num "ground pixels measured" "$(field "$N" ground)" ge 500
num "halo pixels measured" "$(field "$N" halo)" ge 500
# halo opaque: at most 2 % of the halo pixels differ from the 100 % picture
hs=$(field "$N" halo_same); hh=$(field "$N" halo)
num "halo stays opaque (equal pixels, per mille)" "$(( ${hs:-0} * 1000 / ( ${hh:-1} > 0 ? ${hh:-1} : 1 ) ))" ge 980
# ground mixes: at least 50 % of the ground pixels differ from the 100 % picture
gd=$(field "$N" ground_diff); gg=$(field "$N" ground)
num "ground mixes with the backdrop (per mille)" "$(( ${gd:-0} * 1000 / ( ${gg:-1} > 0 ? ${gg:-1} : 1 ) ))" ge 500
# label corner (never ink) differs from the 100 % value at 20 % opacity
num "label corners differ from the 100 % value" "$(field "$N" corner_diff)" ge 5
# COUNTER-PROOF: the old full-rectangle plate leaves (almost) no mixed ground
bd=$(field "$O" ground_diff); bg=$(field "$O" ground)
num "COUNTER-PROOF old plate: mixed ground (per mille)" "$(( ${bd:-9999} * 1000 / ( ${bg:-1} > 0 ? ${bg:-1} : 1 ) ))" le 100
num "COUNTER-PROOF old plate: label corners differing" "$(field "$O" corner_diff)" le 1
echo "platte: $pass ok, $fail fail"
[ "$fail" = 0 ]
