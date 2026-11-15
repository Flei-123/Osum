#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
. tools/lib/mutant.sh
TMPD=$(mktemp -d)
BT=$TMPD/base
cleanup() { git worktree remove --force "$BT" >/dev/null 2>&1; rm -rf "$TMPD"; }
trap cleanup EXIT
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify"
printf 'taskbar-pin|Probe pin|/bin/true\nwindow|Probe window|/bin/true\n' > "$TMPD/ctxmenu.conf"
export EH_ETC_EXTRA="/etc/ctxmenu.conf=$TMPD/ctxmenu.conf@0644"
mutant_tree "$BT" kernel/user/taskthumb.fi capture "return" || { echo "mutant tree failed"; exit 1; }
run_tree() {
    (cd "$1" && DESIGNBUILD="$2/build" bash tools/design/eh6.sh "$2/o" res=1280x800 accel=kvm moreprogs=term progs="$PROGS" tafel=nein pins=explorer,settings \
        extra="animtrace" drehbuch="$ROOT/tools/taskpreview/script.txt" > "$2/run.log" 2>&1)
}
mkdir -p "$TMPD/new" "$TMPD/old"
run_tree "$ROOT" "$TMPD/new" &
run_tree "$BT" "$TMPD/old" &
wait
if [ -n "${TASKPREVIEW_OUT:-}" ]; then
    mkdir -p "$TASKPREVIEW_OUT"
    cp "$TMPD"/new/o/*.ppm "$TMPD/new/o/serial.txt" "$TASKPREVIEW_OUT/" 2>/dev/null
    cp "$TMPD/old/o/a1-card.ppm" "$TASKPREVIEW_OUT/mutant-a1-card.ppm" 2>/dev/null
fi
echo "== new tree =="
python3 -I tools/taskpreview/check.py "$TMPD/new/o" | tee "$TMPD/new.txt"
echo "== counter-proof: mutant without WM_THUMB =="
python3 -I tools/taskpreview/check.py "$TMPD/old/o" mutant | tee "$TMPD/old.txt"
f1=$(grep -c '^  FAIL' "$TMPD/new.txt"); o1=$(grep -c '^  OK' "$TMPD/new.txt")
grep -q 'thumbnail:' <(grep '^  FAIL' "$TMPD/old.txt") && echo "  OK    the mutant card has no picture: the check measures it" \
    || echo "  FAIL  the mutant card still shows a picture"
echo "TASKPREVIEW: $o1 passed, $f1 failed"
[ "$f1" -eq 0 ] && grep -q 'thumbnail:' <(grep '^  FAIL' "$TMPD/old.txt")
