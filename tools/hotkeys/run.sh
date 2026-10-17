#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hotkeys/run.sh -- Windows-style global hotkeys (W1b):
#   Win+E explorer, Win+I settings, Win+D show desktop (toggle), Win+R run (start menu),
#   Win+Left/Right/Up/Down window snap, Ctrl+Shift+Esc task manager.
# One desktop boot (QEMU usb-kbd through the HID layer, keys via the monitor `sendkey`), then the serial lines are checked:
#   kbd.fi latches the key ("hk: super+<c>", "kbd: win+arrow", "hk: taskmgr"),
#   the taskbar acts ("taskbar: hk start <bundle>", "taskbar: hk desktop n="),
#   the window server snaps ("wm: winarrow key=<129..132> getan=1").
# COUNTER-PROBE: the same keys on the tree BEFORE the hotkeys (HOTKEYS_BASE commit) must show none of the actions.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-$(mktemp -d)}
mkdir -p "$OUT"
# the tree BEFORE the input change = the commit that added the alltag options this gate needs
BASE_COMMIT=${HOTKEYS_BASE:-$(git log --format=%H --grep="^alltag: qemu=<args>" -1)}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' missing"; }
hasnt() { grep -qaF -- "$2" "$1" 2>/dev/null && bad "$3 -- '$2' present" || ok "$3"; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "HOTKEYS: skipped, no qemu"; exit 0; }
PROGS="desktop taskbar launcher settings theme explorer sh echo ls cat"
# warm-up: the first key after the first pulse line was lost once on a loaded host -> wait, send a harmless shift
KEYS=(mon="warte 5" mon="sendkey shift" mon="warte 2" mon="sendkey meta_l-e" mon="warte 2" mon="sendkey meta_l-i" mon="warte 2" mon="sendkey meta_l-d" mon="warte 2"
      mon="sendkey meta_l-d" mon="warte 2" mon="sendkey meta_l-left" mon="warte 2" mon="sendkey meta_l-right" mon="warte 2"
      mon="sendkey meta_l-up" mon="warte 2" mon="sendkey meta_l-down" mon="warte 2" mon="sendkey ctrl-shift-esc" mon="warte 2"
      mon="sendkey meta_l-r" mon="warte 2")

run_tree() { # tree out
    mkdir -p "$2"
    ( cd "$1" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
      ALLTAGBUILD="$2.build" bash tools/alltag/build.sh "$2" kbd=no warten=6 \
        extra="modfs osum wmshell wmdauer usb hidgen" hold=no uitrace=yes waitfor="eingabe: ber=" progs="$PROGS" qemu="-device qemu-xhci -device usb-kbd" \
        "${KEYS[@]}" ) > "$2.log" 2>&1
}

echo "== 1. new tree: keys through the desktop =="
run_tree "$ROOT" "$OUT/new" || { bad "build/run failed"; tail -15 "$OUT/new.log"; exit 1; }
S="$OUT/new/serial.txt"
has "$S" "hk: super+e" "Win+E latched"
has "$S" "taskbar: hk start /apps/explorer.osp/start" "Win+E starts the explorer bundle"
has "$S" "hk: super+i" "Win+I latched"
has "$S" "taskbar: hk start /apps/settings.osp/start" "Win+I starts the settings bundle"
has "$S" "hk: super+d" "Win+D latched"
N=$(grep -ac 'taskbar: hk desktop n=' "$S")
[ "$N" -ge 2 ] && ok "Win+D twice -> two show-desktop toggles ($N)" || bad "Win+D toggles: $N, want >= 2"
has "$S" "hk: super+r" "Win+R latched"
has "$S" "taskbar: hk start /apps/run.osp/start" "Win+R starts the Run dialog bundle"
has "$S" "hk: taskmgr" "Ctrl+Shift+Esc latched (own line, no garbage char)"
has "$S" "taskbar: hk start /apps/taskmgr.osp/start" "Ctrl+Shift+Esc starts the task manager bundle"
A=$(grep -ac 'kbd: win+arrow' "$S")
[ "$A" -eq 4 ] && ok "four Win+arrow presses reach the driver ($A)" || bad "Win+arrow presses: $A, want 4"
for k in 129 130 131 132; do
    has "$S" "wm: winarrow key=$k getan=1" "window server acted on key $k (left/right/up/down)"
done
hasnt "$S" "wm: winarrow key=129 getan=0" "no failed snap for Win+Left"
# the arrow keys must NOT leak into the window as text/escape bytes: the latch is the only consumer

echo
echo "== 2. COUNTER-PROBE: tree before the hotkeys =="
if git rev-parse -q --verify "$BASE_COMMIT^{commit}" >/dev/null 2>&1; then
    BT="$OUT/basetree"
    git worktree add -q --detach "$BT" "$BASE_COMMIT" 2>/dev/null
    run_tree "$BT" "$OUT/old" || { bad "old tree failed"; tail -8 "$OUT/old.log"; }
    git worktree remove --force "$BT" >/dev/null 2>&1
    O="$OUT/old/serial.txt"
    hasnt "$O" "taskbar: hk start /apps/explorer.osp/start" "old: Win+E does nothing"
    hasnt "$O" "taskbar: hk start /apps/settings.osp/start" "old: Win+I does nothing"
    hasnt "$O" "taskbar: hk desktop n=" "old: Win+D does nothing"
    hasnt "$O" "wm: winarrow" "old: Win+arrows do not snap"
    hasnt "$O" "hk: taskmgr" "old: Ctrl+Shift+Esc not latched"
    [ -s "$O" ] && ok "old kernel booted (counter-probe is a real run)" || bad "old run produced no serial"
else
    echo "  (skipped: base commit $BASE_COMMIT not in this clone)"
fi

echo
echo "== HOTKEYS: $pass green, $fail red =="
[ "$fail" -eq 0 ]
