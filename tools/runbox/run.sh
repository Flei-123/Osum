#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/runbox/run.sh -- Win+R opens the Run dialog (/bin/runbox), Enter starts what was typed (W1c).
# One desktop boot (QEMU usb-kbd, keys via QMP, every step waits for its serial line), then the serial lines:
#   Win+R           -> "taskbar: hk start /apps/run.osp/start" + "runbox: ready"
#   echo hi + Enter -> "runbox: exec /bin/echo pid=N" (a name without a slash is looked up in /bin)
#   Win+R again, a name that does not exist + Enter -> "runbox: fail /bin/<name>" (the window stays), Esc closes it
# COUNTER-PROBE: the tree before the dialog (Win+R opens the start menu): no "runbox:" line at all.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-$(mktemp -d)}
mkdir -p "$OUT"
BASE_COMMIT=${RUNBOX_BASE:-$(git log --format=%H --grep="^alltag: qemu=<args>" -1)}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' missing"; }
hasnt() { grep -qaF -- "$2" "$1" 2>/dev/null && bad "$3 -- '$2' present" || ok "$3"; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "RUNBOX: skipped, no qemu"; exit 0; }

# event driven (W1d): tools/runbox/drive.py sends the keys through QMP and waits for `runbox: ready` / `exec` / `fail` lines
run_tree() { # tree out progs ready-timeout
    mkdir -p "$2"
    ( cd "$1" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
      ALLTAGBUILD="$2.build" bash tools/alltag/build.sh "$2" kbd=no warten=1 uitrace=yes \
        extra="modfs osum wmshell wmdauer usb hidgen" hold=no waitfor="eingabe: ber=" progs="$3" \
        qemu="-device qemu-xhci -device usb-kbd -qmp unix:$2/qmp.sock,server,nowait" \
        hook="python3 $ROOT/tools/runbox/drive.py $2/qmp.sock $2/serial.txt $2 $4" ) > "$2.log" 2>&1
}

echo "== 1. new tree: Win+R -> dialog -> Enter =="
run_tree "$ROOT" "$OUT/new" "desktop taskbar launcher settings theme explorer sh echo ls cat runbox" 60 \
    || { bad "build/run failed"; tail -n 15 "$OUT/new.log"; exit 1; }
S="$OUT/new/serial.txt"
has "$S" "hk: super+r" "Win+R latched"
has "$S" "taskbar: hk start /apps/run.osp/start" "Win+R starts the run bundle"
N=$(grep -ac '^runbox: ready' "$S")
[ "$N" -ge 2 ] && ok "the dialog opened twice ($N)" || bad "dialog opened $N times, want 2"
has "$S" "runbox: exec /bin/echo pid=" "echo hi + Enter starts /bin/echo (name looked up in /bin)"
has "$S" "runbox: fail /bin/nope" "unknown name: fail line, window stays"
hasnt "$S" "runbox: exec /bin/nope" "unknown name is not started"

echo
echo "== 2. COUNTER-PROBE: tree before the dialog =="
if git rev-parse -q --verify "$BASE_COMMIT^{commit}" >/dev/null 2>&1; then
    BT="$OUT/basetree"
    git worktree add -q --detach "$BT" "$BASE_COMMIT" 2>/dev/null
    run_tree "$BT" "$OUT/old" "desktop taskbar launcher settings theme explorer sh echo ls cat" 12 || { bad "old tree failed"; tail -n 8 "$OUT/old.log"; }
    git worktree remove --force "$BT" >/dev/null 2>&1
    O="$OUT/old/serial.txt"
    [ -s "$O" ] && ok "old kernel booted (counter-probe is a real run)" || bad "old run produced no serial"
    hasnt "$O" "runbox: ready" "old: Win+R shows no run dialog"
    hasnt "$O" "runbox: exec" "old: nothing is started by typing"
else
    echo "  (skipped: base commit $BASE_COMMIT not in this clone)"
fi

echo
echo "== RUNBOX: $pass green, $fail red =="
[ "$fail" -eq 0 ]
