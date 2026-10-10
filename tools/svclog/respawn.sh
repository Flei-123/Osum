#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/svclog/respawn.sh -- THE DESKTOP RESTARTS `jarvisd` WHEN ITS SUPERVISOR IS GONE, WITH BACK-OFF.
#
#   /root/jarvis/bin/heavy bash tools/svclog/respawn.sh
#
# Machine of the stick + boot word `jarvis` + /bin/jarvisd WITHOUT a permission list: the helper ends at once
# ("no permission list -- nothing allowed"). Expected on the serial line: `desk: jarvisd ended pid=N`, then
# `desk: jarvisd restart in (s)=5`, `=10`, `=20` ... (doubling, cap 60) and a new `desk: start /bin/jarvisd`.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
export DESIGNBUILD="$TMPD/build" APPS="fetch jarvisd"
printf 'warte 75\n' > "$TMPD/script.txt"
bash tools/design/eh6.sh "$TMPD/run" accel=kvm "progs=desktop taskbar settings launcher explorer netview edit sh echo ls cat ps dhcp host ping" \
    "extra=jarvis" drehbuch="$TMPD/script.txt" > "$TMPD/run.log" 2>&1
S="$TMPD/run/serial.txt"
n=$(grep -ac 'desk: start /bin/jarvisd' "$S"); [ "$n" -ge 3 ] && ok "jarvisd was started $n times (boot + restarts)" || bad "jarvisd started only $n times"
e=$(grep -ac 'desk: jarvisd ended pid=' "$S"); [ "$e" -ge 2 ] && ok "the desktop noticed the end $e times" || bad "end noticed only $e times"
w=$(grep -a 'desk: jarvisd restart in (s)=' "$S" | sed 's/.*=//' | tr '\n' ' ')
echo "        waits: $w"
set -- $w
[ $# -ge 3 ] && [ "$1" = 5 ] && [ "$2" = 10 ] && [ "$3" = 20 ] && ok "back-off doubles: 5, 10, 20" || bad "back-off wrong: $w"
echo "== $pass ok, $fail fail =="
[ "$fail" = 0 ]
