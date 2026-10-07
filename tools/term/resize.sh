#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/term/resize.sh -- r468: a running full-screen program must follow the window size (SIGWINCH).
# Start through /root/jarvis/bin/heavy. Opens `edit`, maximises the terminal window, and checks that the help line
# moved down to the LAST row of the bigger grid.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
bash tools/design/eh6.sh "$TMPD/run" accel=kvm drehbuch=tools/term/resize.txt > "$TMPD/run.log" 2>&1
S="$TMPD/run/serial.txt"
cp "$S" /root/resize.serial 2>/dev/null
grep -a "kgui: winch\|wm: term win" "$S" | tail -6
python3 tools/term/resize.py "$S" && ok "edit redrew for the bigger window (help line on the last row)" \
    || bad "edit did not follow the resize"
mkdir -p docs/shots/term
for n in 11-before 12-maximised; do
    [ -s "$TMPD/run/$n.ppm" ] && python3 tools/design/ppm2png.py "$TMPD/run/$n.ppm" "docs/shots/term/$n.png" >/dev/null 2>&1
done
echo "TERM-RESIZE: $pass passed, $fail failed"
[ "$fail" = 0 ]
