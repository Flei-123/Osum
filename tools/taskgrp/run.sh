#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/taskgrp/run.sh -- taskbar grouping: terminal + two Explorer windows + Settings = THREE buttons, the Explorer one with `taskbar: grp i= n=2`.
# COUNTER-PROBE: the tree before the grouping commit shows FOUR buttons and no grp line.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-$(mktemp -d)}
mkdir -p "$OUT"
BASE_COMMIT=${TASKGRP_BASE:-$(git log --format=%H --grep="^taskbar: group windows of one program" -1 | xargs -r -I{} git rev-parse {}^)}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "TASKGRP: skipped, no qemu"; exit 0; }
PROGS="desktop taskbar launcher settings theme explorer sh echo ls cat"
run_tree() { # tree out
    mkdir -p "$2"
    ( cd "$1" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
      ALLTAGBUILD="$2.build" bash tools/alltag/build.sh "$2" kbd=no warten=1 \
        extra="modfs osum wmshell wmdauer usb hidgen" hold=no uitrace=yes waitfor="eingabe: ber=" progs="$PROGS" \
        qemu="-device qemu-xhci -device usb-kbd -qmp unix:$2/qmp.sock,server,nowait" \
        hook="python3 $ROOT/tools/taskgrp/drive.py $2/qmp.sock \$SOCK $2/serial.txt $2" ) > "$2.log" 2>&1
}
fact() { sed -n "s/^$2=//p" "$1/scenes.txt" 2>/dev/null | tail -1; }
echo "== 1. new tree =="
run_tree "$ROOT" "$OUT/new" || true
[ -s "$OUT/new/scenes.txt" ] || { bad "driver wrote no scenes.txt"; tail -15 "$OUT/new.log"; echo "== TASKGRP: $pass green, $fail red =="; exit 1; }
N="$OUT/new"
[ "$(fact $N buttons)" = 3 ] && ok "terminal + two Explorer windows + Settings = 3 buttons" || bad "buttons=$(fact $N buttons), want 3"
[ "$(fact $N grp_max)" = 2 ] && ok "the Explorer button reports n=2" || bad "grp_max=$(fact $N grp_max), want 2"
echo
echo "== 2. COUNTER-PROBE: tree before the grouping =="
if [ -n "$BASE_COMMIT" ] && git rev-parse -q --verify "$BASE_COMMIT^{commit}" >/dev/null 2>&1; then
    BT="$OUT/basetree"
    git worktree add -q --detach "$BT" "$BASE_COMMIT" 2>/dev/null
    mkdir -p "$BT/tools/taskgrp" && cp tools/taskgrp/drive.py "$BT/tools/taskgrp/"
    run_tree "$BT" "$OUT/old" || true
    git worktree remove --force "$BT" >/dev/null 2>&1
    O="$OUT/old"
    [ -s "$O/scenes.txt" ] && ok "old tree booted and was driven" || bad "old run wrote no scenes.txt"
    [ "$(fact $O buttons)" = 4 ] && ok "old: 4 buttons (no grouping)" || bad "old: buttons=$(fact $O buttons), want 4"
    [ "$(fact $O grp_lines)" = 0 ] && ok "old: no grp lines" || bad "old: grp lines present"
else
    echo "  (skipped: base commit '$BASE_COMMIT' not in this clone)"
fi
echo
echo "== TASKGRP: $pass green, $fail red =="
[ "$fail" -eq 0 ]
