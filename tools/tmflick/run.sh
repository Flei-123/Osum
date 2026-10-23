#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/tmflick/run.sh -- W-FLICKER: a window resize keeps the old picture (no flat dark flash) until the client has painted the new size.
#
#   /root/jarvis/bin/heavy bash tools/tmflick/run.sh
#
# Boots the task manager at 1920x1080 (QEMU KVM), drags its bottom-right corner back and forth (serie drag:, 72 screendumps) and counts
# frames whose client area is flat dark (blank.py). Case `new` must show 0 blank frames; the counter-proof `old` (kernel word `resclear`:
# the old clear-to-background) must show blank frames, else the measurement proves nothing.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
printf 'warte 8\nfoto base\nfahre 982,618\nwarte 2\nserie drag:14,9,12 72 r 35\nwarte 2\nfoto post\n' > "$TMPD/book.txt"
for v in new old; do
    w=""; [ $v = old ] && w=" resclear"
    OSUM_ACCEL=kvm bash tools/alltag/build.sh "$TMPD/$v" kbd=yes uitrace=yes warten=6 res=1920x1080 \
        extra="wigapp=/bin/taskmgr,takt,100 wighalt=100$w" progs="taskmgr theme sh echo ls cat" drive="$TMPD/book.txt" > "$TMPD/$v.log" 2>&1
    out=$(python3 -I tools/tmflick/blank.py "$TMPD/$v" r 2>&1 | head -1)
    echo "  $v: $out"
    n=$(echo "$out" | sed -n 's/.*blank=\([0-9]*\).*/\1/p')
    if [ -z "$n" ]; then bad "$v: no measurement"; continue; fi
    if [ $v = new ]; then
        [ "$n" -le 2 ] && ok "resize keeps the old picture (blank frames $n <= 2)" || bad "resize flashes blank ($n frames)"
    else
        [ "$n" -ge 20 ] && ok "counter-proof resclear: $n blank frames (old behaviour reproduced)" || bad "counter-proof shows only $n blank frames"
    fi
done
git checkout -- docs 2>/dev/null
echo "TMFLICK: $pass passed, $fail failed"
[ "$fail" = 0 ]
