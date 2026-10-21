#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/frameprof/run.sh -- MON-1 gate: per-window present counters (kernel/ui/frameprof.fi).
#
#   bash tools/frameprof/run.sh
#
# Run A (`framesdump=500`): the kernel prints `frames: win=<i> presents= avg_us= max_us=` per window and
#   `frames: total= note_cyc=` every 500 ticks.
#   - at least two dump rounds, the totals only grow
#   - at least one window row with presents > 0 and avg_us > 0, and one with the owner pid= > 0 (T1-S6 key: /proc/frames win.<i>.pid)
#   - the measured cost of one counter update (note_cyc, TSC cycles) stays under 2000 (overhead budget)
#   - no panic on the serial line
# Run B (no word): counter-proof, no `frames:` line at all.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq"
MAXCYC=${FRAMEPROF_MAX_CYC:-2000}

cat > "$TMPD/dreh.txt" <<EOT
warteauf 'taskbar: health' || 240
warte 25
foto 00-end
EOT

run_one() { # <name> <extra words>
    mkdir -p "$TMPD/$1"
    ( DESIGNBUILD="$TMPD/$1/build" bash tools/design/eh6.sh "$TMPD/$1/o" res=1280x800 accel=kvm tafel=nein pins=terminal,explorer progs="$PROGS" \
        extra="$2" drehbuch="$TMPD/dreh.txt" > "$TMPD/$1/o.log" 2>&1 )
}
field() { echo "$1" | grep -a -o " $2=[0-9]*" | head -1 | cut -d= -f2; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
run_one a "framesdump=500" &
run_one b "" &
wait
SA="$TMPD/a/o/serial.txt"; SB="$TMPD/b/o/serial.txt"
if [ -n "${FRAMEPROF_OUT:-}" ]; then
    mkdir -p "$FRAMEPROF_OUT"
    cp "$SA" "$FRAMEPROF_OUT/serial-a.txt" 2>/dev/null; cp "$SB" "$FRAMEPROF_OUT/serial-b.txt" 2>/dev/null
fi
[ -s "$SA" ] && [ -s "$SB" ] || { bad "no serial output: $(tail -n 3 "$TMPD/a/o.log" | tr '\n' ' ')"; echo "FRAMEPROF: $pass passed, $fail failed"; exit 1; }

nt=$(grep -ac '^frames: total=' "$SA")
[ "$nt" -ge 2 ] && ok "A: $nt dump rounds" || bad "A: expected >= 2 dump rounds, found $nt"
first=$(field "$(grep -a '^frames: total=' "$SA" | head -1 | sed 's/total=/ total=/')" total)
lastl=$(grep -a '^frames: total=' "$SA" | tail -1 | sed 's/total=/ total=/')
last=$(field "$lastl" total)
[ -n "$first" ] && [ -n "$last" ] && [ "$last" -gt "$first" ] && ok "A: presents grow ($first -> $last)" || bad "A: presents do not grow ($first -> $last)"
rows=$(grep -a '^frames: win=' "$SA" | awk '{split($3,p,"="); split($4,a,"="); if (p[2]+0>0 && a[2]+0>0) n++} END{print n+0}')
[ "$rows" -ge 1 ] && ok "A: $rows window rows with presents > 0 and avg_us > 0" || bad "A: no usable window row"
pidrows=$(grep -a '^frames: win=' "$SA" | awk '{for(i=1;i<=NF;i++){if($i ~ /^pid=/){split($i,q,"="); if(q[2]+0>0) n++}}} END{print n+0}')
[ "$pidrows" -ge 1 ] && ok "A: $pidrows window rows name their owner pid (pid= > 0; taskmgr FPS column key)" || bad "A: no row with pid= > 0"
cyc=$(field "$lastl" note_cyc)
[ -n "$cyc" ] && [ "$cyc" -gt 0 ] && [ "$cyc" -le "$MAXCYC" ] && ok "A: counter update costs $cyc TSC cycles (<= $MAXCYC)" || bad "A: note_cyc '$cyc' missing, zero or > $MAXCYC"
echo "  INFO  presents=$last note_cyc=$cyc"
grep -aiqE 'panic|kernel fault|exception' "$SA" && bad "A: panic/fault on the serial line" || ok "A: 0 panics"
nb=$(grep -acE '^frames: (win|total)=' "$SB")
[ "$nb" = 0 ] && ok "B: no frames line without the word (counter-proof)" || bad "B: $nb frames lines without the word"
echo "FRAMEPROF: $pass passed, $fail failed"
[ "$fail" = 0 ]
