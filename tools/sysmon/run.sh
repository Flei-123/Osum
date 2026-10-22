#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/sysmon/run.sh -- MON-2 gate: the 1 Hz system sampler (kernel/ui/sysmon.fi, /proc/sysmon).
#
#   /root/jarvis/bin/heavy bash tools/sysmon/run.sh
#
# Run A (`sysmondump=500`): the kernel prints `sysmon: n= cpu= free= rd= wr= rx= tx= cyc= taken=` every 500 ticks.
#   - at least three dump rounds; the sample count n grows and never exceeds 60 (the ring size)
#   - the sampler takes about one sample per second (taken grows by >= 3 between the first and last round)
#   - frames free > 0, cpu busy percentage within 0..100
#   - disk reads and tick-independent counters never go backwards
#   - the cost of one sample stays under 20000 TSC cycles
#   - no panic on the serial line
# Run B (no word): counter-proof, no `sysmon:` line at all.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq"
MAXCYC=${SYSMON_MAX_CYC:-20000}

cat > "$TMPD/dreh.txt" <<EOT
warteauf 'taskbar: health' || 240
warte 25
foto 00-end
EOT

run_one() {
    mkdir -p "$TMPD/$1"
    ( DESIGNBUILD="$TMPD/$1/build" bash tools/design/eh6.sh "$TMPD/$1/o" res=1280x800 accel=kvm tafel=nein pins=terminal,explorer progs="$PROGS" \
        extra="$2" drehbuch="$TMPD/dreh.txt" > "$TMPD/$1/o.log" 2>&1 )
}
field() { echo "$1" | grep -a -o " $2=[0-9]*" | head -1 | cut -d= -f2; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
run_one a "sysmondump=500" &
run_one b "" &
wait
SA="$TMPD/a/o/serial.txt"; SB="$TMPD/b/o/serial.txt"
if [ -n "${SYSMON_OUT:-}" ]; then
    mkdir -p "$SYSMON_OUT"
    cp "$SA" "$SYSMON_OUT/serial-a.txt" 2>/dev/null; cp "$SB" "$SYSMON_OUT/serial-b.txt" 2>/dev/null
fi
[ -s "$SA" ] && [ -s "$SB" ] || { bad "no serial output: $(tail -n 3 "$TMPD/a/o.log" | tr '\n' ' ')"; echo "SYSMON: $pass passed, $fail failed"; exit 1; }

L=$(grep -a '^sysmon: n=' "$SA" | sed 's/sysmon: n=/ n=/')
nl=$(echo "$L" | grep -c ' n=')
[ "$nl" -ge 3 ] && ok "A: $nl dump rounds" || bad "A: expected >= 3 dump rounds, found $nl"
first=$(echo "$L" | head -1); lastl=$(echo "$L" | tail -1)
n1=$(field "$first" n); n2=$(field "$lastl" n)
[ -n "$n1" ] && [ -n "$n2" ] && [ "$n2" -gt "$n1" ] && [ "$n2" -le 60 ] && ok "A: sample count grows within the ring ($n1 -> $n2 <= 60)" || bad "A: sample count $n1 -> $n2"
t1=$(field "$first" taken); t2=$(field "$lastl" taken)
[ -n "$t1" ] && [ -n "$t2" ] && [ $((t2 - t1)) -ge 3 ] && ok "A: about one sample per second (taken $t1 -> $t2)" || bad "A: sampling rate (taken $t1 -> $t2)"
fr=$(field "$lastl" free)
[ -n "$fr" ] && [ "$fr" -gt 0 ] && ok "A: frames free $fr" || bad "A: frames free '$fr'"
bad_cpu=$(echo "$L" | awk '{for(i=1;i<=NF;i++){if($i ~ /^cpu=/){split($i,q,"="); if(q[2]+0>100) n++}}} END{print n+0}')
[ "$bad_cpu" = 0 ] && ok "A: cpu busy within 0..100 on every round" || bad "A: $bad_cpu rounds with cpu > 100"
back=$(echo "$L" | awk '{for(i=1;i<=NF;i++){if($i ~ /^rd=/){split($i,q,"="); if(q[2]+0<p) n++; p=q[2]+0}}} END{print n+0}')
[ "$back" = 0 ] && ok "A: disk read counter never goes backwards" || bad "A: disk read counter went backwards $back times"
rd=$(field "$lastl" rd)
[ -n "$rd" ] && [ "$rd" -gt 0 ] && ok "A: disk reads seen ($rd blocks)" || bad "A: no disk reads counted"
cyc=$(field "$lastl" cyc)
[ -n "$cyc" ] && [ "$cyc" -gt 0 ] && [ "$cyc" -le "$MAXCYC" ] && ok "A: one sample costs $cyc TSC cycles (<= $MAXCYC)" || bad "A: cyc '$cyc' missing, zero or > $MAXCYC"
echo "  INFO  n=$n2 cpu=$(field "$lastl" cpu) free=$fr rd=$rd wr=$(field "$lastl" wr) rx=$(field "$lastl" rx) tx=$(field "$lastl" tx) cyc=$cyc"
grep -aiqE 'panic|kernel fault|exception' "$SA" && bad "A: panic/fault on the serial line" || ok "A: 0 panics"
nb=$(grep -ac '^sysmon: n=' "$SB")
[ "$nb" = 0 ] && ok "B: no sysmon line without the word (counter-proof)" || bad "B: $nb sysmon lines without the word"
echo "SYSMON: $pass passed, $fail failed"
[ "$fail" = 0 ]
