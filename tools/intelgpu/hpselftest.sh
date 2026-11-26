#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
PROC=${INTELGPU_PROC:-/proc/intelgpu}
REPORT=${1:-/root/intelgpu-selftest.txt}
pass=0
fail=0
skip=0

say() { printf '%s\n' "$1" >> "$REPORT"; }
val() { sed -n "s/^$1=\([^ ]*\).*/\1/p" "$PROC" | head -n 1; }
ok() { pass=$((pass+1)); say "PASS $1"; }
bad() { fail=$((fail+1)); say "FAIL $1"; }
na() { skip=$((skip+1)); say "SKIP $1"; }

expect() {
    got=$(val "$1")
    if [ -z "$got" ]; then
        na "$1 missing (boot word for this stage not set)"
    elif [ "$got" = "$2" ]; then
        ok "$1=$got"
    else
        bad "$1=$got expected $2"
    fi
}

: > "$REPORT"
say "intelgpu selftest $(date 2>/dev/null)"
if [ ! -r "$PROC" ]; then
    say "FAIL $PROC not readable; boot with words: intelgpu intelgpuedid intelgpuflip intelgpublit"
    exit 2
fi
say "--- raw ---"
cat "$PROC" >> "$REPORT"
say "--- checks ---"
head -n 1 "$PROC" | grep -q 'no device\|off\|bad bar0\|not probed' && bad "driver state: $(head -n 1 "$PROC")" || ok "driver state"
expect edid_status 7
expect flip_status 7
expect flip_rollback 0
expect blit_status 7
expect blit_verified 1
expect blit_hangs 0
expect blit_errors 0
expect mode_status 7
denied=$(val denied)
[ -n "$denied" ] && say "INFO denied=$denied"
say "RESULT pass=$pass fail=$fail skip=$skip"
printf 'intelgpu selftest: pass=%s fail=%s skip=%s report=%s\n' "$pass" "$fail" "$skip" "$REPORT"
[ "$fail" = 0 ]
