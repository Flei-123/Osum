#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/stall/run.sh -- STAB-3 gate: the freeze detector (kernel/diag/stall.fi).
#
#   bash tools/stall/run.sh
#
# The detector runs in the timer bottom half: input arrived (key / pointer packet) and the desktop loop completed no round for
# more than 100 ticks -> `stall: input without desktop round <ticks> rounds= frames= inputs= n= t=`, then the task table
# (`task: pid=...` lines) and `stall: syscalls <slot>:<number> ...` (newest first, ring of 32).
# Run A (`stallspin=400`): planted spin -- the desktop loop busy-waits 4 s after the first input. Must report exactly one stall with
#   the task table and the syscall list, and the desktop must still draw afterwards (second `taskbar`-independent: round counter moves on).
# Run B (clean, same input): 0 stall lines. Together A and B are the counter-proof: the gate goes red on a spin, green on a clean run.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq"
cat > "$TMPD/dreh.txt" <<EOT
warteauf 'taskbar: health' || 240
warte 4
taste esc
warte 3
taste esc
warte 8
foto 00-end
EOT
run_one() { # <name> <extra words>
    mkdir -p "$TMPD/$1"
    ( DESIGNBUILD="$TMPD/$1/build" bash tools/design/eh6.sh "$TMPD/$1/o" res=1280x800 accel=kvm tafel=nein progs="$PROGS" \
        extra="$2" drehbuch="$TMPD/dreh.txt" > "$TMPD/$1/o.log" 2>&1 )
}
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
run_one a "stallspin=400" &
run_one b "" &
wait
SA="$TMPD/a/o/serial.txt"; SB="$TMPD/b/o/serial.txt"
if [ -n "${STALL_OUT:-}" ]; then
    mkdir -p "$STALL_OUT"; cp "$SA" "$STALL_OUT/serial-a.txt" 2>/dev/null; cp "$SB" "$STALL_OUT/serial-b.txt" 2>/dev/null
fi
for r in a b; do
    [ -s "$TMPD/$r/o/serial.txt" ] || { bad "run $r: no serial output: $(tail -n 3 "$TMPD/$r/o.log" | tr '\n' ' ')"; }
done
if [ "$fail" -gt 0 ]; then echo "STALL: $pass passed, $fail failed"; exit 1; fi
na=$(grep -ac '^stall: input without desktop round ' "$SA")
[ "$na" = 1 ] && ok "A planted spin: exactly one stall report" || bad "A planted spin: expected 1 stall report, found $na"
line=$(grep -a -m1 '^stall: input without desktop round ' "$SA")
dur=$(echo "$line" | sed -E 's/^stall: input without desktop round ([0-9]+) .*/\1/')
[ -n "$dur" ] && [ "$dur" -ge 100 ] && [ "$dur" -le 400 ] && ok "A: stalled $dur ticks when reported (100..400)" || bad "A: bad duration '$dur': $line"
nt=$(awk '/^stall: input without desktop round /{f=1;next} /^stall: syscalls/{f=0} f&&/^task: pid=/{n++} END{print n+0}' "$SA")
[ "$nt" -ge 5 ] && ok "A: task table follows the report ($nt tasks)" || bad "A: task table missing ($nt rows)"
ns=$(grep -a -m1 '^stall: syscalls' "$SA" | wc -w)
[ "$ns" -ge 10 ] && ok "A: syscall list present ($((ns - 2)) entries)" || bad "A: syscall list too short"
grep -a -m1 '^stall: syscalls' "$SA" | grep -qE ' [0-9]+:[0-9]+' && ok "A: entries have slot:number form" || bad "A: syscall entries malformed"
grep -aiqE 'panic|kernel fault' "$SA" && bad "A: panic on the serial line" || ok "A: 0 panics"
if [ -s "$TMPD/a/o/00-end.ppm" ]; then ok "A: desktop still drew a picture after the spin"; else bad "A: no picture after the spin"; fi
nb=$(grep -ac '^stall: ' "$SB")
[ "$nb" = 0 ] && ok "B clean: 0 stall lines" || bad "B clean: $nb stall lines: $(grep -a -m2 '^stall: ' "$SB" | tr '\n' '|')"
grep -aq '^taskbar: health ' "$SB" && ok "B clean: desktop came up" || bad "B clean: no taskbar health"
echo; echo "STALL: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
