#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/cliphist/run.sh -- D-015: Win+V opens the clipboard history popup (/bin/cliphist), a row puts its entry on top again.
# One desktop boot (QEMU usb-kbd, keys via QMP, every step waits for its serial line):
#   Win+R `cliphist put alpha beta gamma` -> three bus entries
#   Win+V -> rows gamma beta alpha; Tab+Enter picks beta -> the bus head is beta
#   Win+V -> ring n=4 but 3 rows (the older beta is not shown twice); key 3 picks alpha
#   Win+V -> Down+Enter picks row 1; Win+V -> Esc closes without a pick
# COUNTER-PROBE: the tree before the popup: Win+V shows nothing, `cliphist` does not exist ("runbox: fail /bin/cliphist").
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-$(mktemp -d)}
[ -n "${1:-}" ] || trap 'rm -rf "$OUT"' EXIT
mkdir -p "$OUT"
BASE_COMMIT=${CLIPHIST_BASE:-$(git log --format=%H --grep="^cliphist: Win+V" -1 | xargs -r -I{} git rev-parse {}^)}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' missing"; }
hasnt() { grep -qaF -- "$2" "$1" 2>/dev/null && bad "$3 -- '$2' present" || ok "$3"; }
fact() { [ "$(grep -a "^$2=" "$1" 2>/dev/null | tail -1 | cut -d= -f2)" = 1 ] && ok "$3" || bad "$3 ($2 != 1)"; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "CLIPHIST: skipped, no qemu"; exit 0; }

run_tree() { # tree out progs timeout
    mkdir -p "$2"
    ( cd "$1" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
      ALLTAGBUILD="$2.build" bash tools/alltag/build.sh "$2" kbd=no warten=1 uitrace=yes \
        extra="modfs osum wmshell wmdauer usb hidgen" hold=no waitfor="eingabe: ber=" progs="$3" \
        qemu="-device qemu-xhci -device usb-kbd -qmp unix:$2/qmp.sock,server,nowait" \
        hook="python3 $ROOT/tools/cliphist/drive.py $2/qmp.sock $2/serial.txt $2 $4" ) > "$2.log" 2>&1
}

echo "== 1. new tree: Win+V -> history popup =="
run_tree "$ROOT" "$OUT/new" "desktop taskbar launcher settings theme explorer sh echo ls cat runbox cliphist" 60 \
    || { bad "build/run failed"; tail -n 15 "$OUT/new.log"; exit 1; }
S="$OUT/new/serial.txt"; F="$OUT/new/scenes.txt"
has "$S" "hk: super+v" "Win+V latched"
has "$S" "taskbar: hk start /apps/cliphist.osp/start" "Win+V starts the cliphist bundle"
fact "$F" seed "three entries put through the Run dialog"
fact "$F" open1 "popup opens"
fact "$F" ring3 "ring holds 3, 3 rows shown"
fact "$F" rows1 "rows newest first: gamma, beta, alpha"
fact "$F" pick_beta "Tab + Enter picks row 1 (beta)"
fact "$F" head_beta "the bus head is now beta (what Ctrl+V pastes)"
fact "$F" closed1 "the window closes after a pick"
fact "$F" open2 "popup opens again"
fact "$F" ring4 "ring holds 4 (beta twice), 3 rows shown"
fact "$F" rows2 "rows: beta, gamma, alpha (no duplicate)"
fact "$F" pick_digit "key 3 picks row 2 (alpha)"
fact "$F" head_alpha "the bus head is now alpha"
fact "$F" open3 "popup opens a third time"
fact "$F" pick_down "Down + Enter picks row 1"
fact "$F" open4 "popup opens a fourth time"
fact "$F" esc_nopick "Esc closes without a pick"

echo
echo "== 2. COUNTER-PROBE: tree before the popup =="
if [ -n "$BASE_COMMIT" ] && git rev-parse -q --verify "$BASE_COMMIT^{commit}" >/dev/null 2>&1; then
    BT="$OUT/basetree"
    git worktree add -q --detach "$BT" "$BASE_COMMIT" 2>/dev/null
    run_tree "$BT" "$OUT/old" "desktop taskbar launcher settings theme explorer sh echo ls cat runbox" 12 || { bad "old tree failed"; tail -n 8 "$OUT/old.log"; }
    git worktree remove --force "$BT" >/dev/null 2>&1
    O="$OUT/old/serial.txt"
    [ -s "$O" ] && ok "old kernel booted (counter-probe is a real run)" || bad "old run produced no serial"
    hasnt "$O" "cliphist: ready" "old: Win+V shows no popup"
    hasnt "$O" "cliphist: put n=" "old: no cliphist program"
    has "$O" "runbox: fail /bin/cliphist" "old: the Run dialog cannot start cliphist"
else
    echo "  (skipped: no base commit '^cliphist: Win+V' yet -- set CLIPHIST_BASE)"
fi

echo
echo "== CLIPHIST: $pass green, $fail red =="
[ "$fail" -eq 0 ]
