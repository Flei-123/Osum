#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/term/multi.sh -- several terminal windows at once (Dell, 10.10.2026: only ONE terminal could be opened).
# Start through /root/jarvis/bin/heavy. Boots the stick's machine WITH /bin/term, opens the Terminal from the start menu
# four times and reads every window's cells from the serial line (`wm: termwin`, `wm: tw<slot> <row> [text]`).
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
MODE=${1:+extra=$1}   # `nocascade` = counter-proof: the old fixed window start
bash tools/design/eh6.sh "$TMPD/run" accel=kvm moreprogs="term termfull ptytest" drehbuch=tools/term/multi.txt $MODE > "$TMPD/run.log" 2>&1
S="$TMPD/run/serial.txt"
if [ -n "${MULTI_KEEP:-}" ]; then
    mkdir -p "$MULTI_KEEP"; cp "$S" "$TMPD/run.log" "$MULTI_KEEP/"
    for n in "$TMPD"/run/*.ppm; do python3 tools/design/ppm2png.py "$n" "$MULTI_KEEP/$(basename "$n" .ppm).png" > /dev/null 2>&1; done
fi
tail -3 "$TMPD/run.log"
grep -a "launcher: start\|term:" "$S" | head -12
python3 tools/term/multi.py "$S"; rc=$?
echo "TERM-MULTI: exit $rc"
exit $rc
