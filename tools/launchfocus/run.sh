#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/launchfocus/run.sh -- a program started from the Start menu search comes up in front, focused and highlighted; a context menu stays clean over a repainting window.
#
#   [BASE=<rev>] bash tools/launchfocus/run.sh
#
# Machine of the stick (tools/design/eh6.sh, 1280x800, KVM). Drehbuch tools/launchfocus/script.txt, checks tools/launchfocus/check.py.
#   A. Win + "terminal" + Enter twice while a terminal is already open: each start opens a NEW window that takes the focus
#      (`wm: fokus`), has the active title colour while all older ones are inactive, the task bar button marks it, typed keys land in it.
#      CONTROL: a click on the first terminal takes the focus away again (the title colour really measures the focus).
#   B. Right click on the desktop below the task manager: the menu (167x120, flipped up) lies over the repainting window, no stale picture of
#      the menu stays at the top left (0,0) while it is open, the menu is unchanged after 6 s of repaints, Esc closes it.
# COUNTER-PROOF: the tree before the fix (BASE, default origin/main) leaves the menu picture at 0,0 on the first open.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
BT=$TMPD/base
cleanup() { git worktree remove --force "$BT" >/dev/null 2>&1; rm -rf "$TMPD"; }
trap cleanup EXIT
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify"
BASE=${BASE:-origin/main}
git worktree add --detach "$BT" "$BASE" > /dev/null 2>&1
run_tree() {
    (cd "$1" && DESIGNBUILD="$2/build" bash tools/design/eh6.sh "$2/o" res=1280x800 accel=kvm moreprogs=term progs="$PROGS" tafel=nein drehbuch="$ROOT/tools/launchfocus/script.txt" > "$2/run.log" 2>&1)
}
mkdir -p "$TMPD/new" "$TMPD/old"
run_tree "$ROOT" "$TMPD/new" &
run_tree "$BT" "$TMPD/old" &
wait
echo "== new tree =="
python3 -I tools/launchfocus/check.py "$TMPD/new/o" | tee "$TMPD/new.txt"
f1=$(grep -c '^  FAIL' "$TMPD/new.txt"); o1=$(grep -c '^  OK' "$TMPD/new.txt")
echo "== counter-proof: the tree before the fix ($BASE) =="
python3 -I tools/launchfocus/check.py "$TMPD/old/o" | tee "$TMPD/old.txt"
f2=$(grep -c '^  FAIL' "$TMPD/old.txt")
grep -q 'no stale menu picture' <(grep '^  FAIL' "$TMPD/old.txt") && echo "  OK    the old tree shows the stale menu picture: the check measures it" || echo "  FAIL  the old tree does not show the stale menu picture"
echo "== result =="
[ "$f1" -eq 0 ] && [ "$o1" -ge 14 ] && echo "  OK    all $o1 checks pass" || echo "  FAIL  $f1 failed ($o1 ok)"
[ "$f1" -eq 0 ] && [ "$o1" -ge 14 ] && grep -q 'no stale menu picture' <(grep '^  FAIL' "$TMPD/old.txt")
