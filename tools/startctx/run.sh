#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/startctx/run.sh -- Start menu: right click on a pinned tile opens a context menu (start, unpin, pin to taskbar).
#
#   bash tools/startctx/run.sh
#
# Machine of the stick (tools/design/eh6.sh, 1280x800). Window origin (8,336), pinned tile i is at x=28+100*i, y=436, 100x88.
#   1. Super, right click on the 2nd tile (Settings): `launcher: ctx open i=1`
#   2. click row 2 (unpin): `ctx pick i=2`, `unpin start settings.osp`, the grid shrinks (`pin=4` -> `pin=3`)
#   3. right click on the 1st tile, click row 3: `ctx pick i=3`, `pin taskbar explorer.osp`
#   4. right click, Escape: a menu opened, no further `ctx pick`
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify"
cat > "$TMPD/dreh.txt" <<'EOT'
warteauf 'launcher: ready' || 120
warte 6
taste meta_l
warte 8
rklick 178,480
warte 3
foto 01-menu
klick 240,526
warte 4
rklick 78,480
warte 3
klick 138,554
warte 4
rklick 78,480
warte 3
taste esc
warte 3
foto 02-end
EOT
DESIGNBUILD="$TMPD/build" bash tools/design/eh6.sh "$TMPD/o" res=1280x800 accel=kvm progs="$PROGS" drehbuch="$TMPD/dreh.txt" > "$TMPD/o.log" 2>&1
S="$TMPD/o/serial.txt"
grep -aq 'launcher: ctx open i=1' "$S" && ok "right click on a pinned tile opens the menu" || bad "no 'ctx open i=1'"
grep -aq 'launcher: ctx pick i=2' "$S" && grep -aq 'launcher: unpin start settings.osp' "$S" && ok "unpin from Start" || bad "unpin missing"
grep -a 'launcher: w11 home=1' "$S" | tail -1 | grep -aq 'pin=3' && ok "the grid lost the tile (pin=3)" || bad "grid did not shrink"
grep -aq 'launcher: ctx pick i=3' "$S" && grep -aq 'launcher: pin taskbar explorer.osp' "$S" && ok "pin to taskbar" || bad "pin to taskbar missing"
n=$(grep -ac 'launcher: ctx pick' "$S"); n_open=$(grep -ac 'launcher: ctx open' "$S")
[ "$n_open" -ge 3 ] && [ "$n" -eq 2 ] && ok "Escape closes the menu without a pick ($n_open opens, $n picks)" || bad "esc: opens=$n_open picks=$n"
grep -aq 'launcher: start refused' "$S" && bad "a start was refused" || ok "no refused start"
echo "startctx: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
