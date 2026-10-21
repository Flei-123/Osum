#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/shellsup/run.sh -- STAB-2 gate: the kernel supervises the taskbar and the launcher.
#
#   bash tools/shellsup/run.sh
#
# Run A (`tbkill=3000`): the supervisor kills the taskbar once, 30 s after its start, and must bring it back.
#   - one `taskbar: health` line per taskbar start, two in total, `pins=` and `paints=` filled
#   - `desk: shell taskbar ended`, then `respawn` with gap <= 150 ticks, new bar up (second health) < 3000 ms after the kill
#   - the bar rectangle after the respawn shows the same content as before (left part, clock excluded)
#   - no panic / fault on the serial line
# Run B (`tbkill=3000 nosup`): control. Same kill, supervisor off: no respawn, no second health line, the bar rectangle is gone
# from the picture (many pixels differ) -- proves the pixel check sees a missing bar.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq"

cat > "$TMPD/dreh_a.txt" <<EOT
warteauf 'taskbar: health' || 240
warte 4
foto 00-before
warteauf 'desk: shell taskbar respawn' || 90
warte 10
foto 01-after
EOT
cat > "$TMPD/dreh_b.txt" <<EOT
warteauf 'taskbar: health' || 240
warte 4
foto 00-before
warteauf 'desk: shell taskbar killed' || 90
warte 12
foto 01-after
EOT

run_one() { # <name> <drehbuch> <extra words>
    mkdir -p "$TMPD/$1"
    ( DESIGNBUILD="$TMPD/$1/build" bash tools/design/eh6.sh "$TMPD/$1/o" res=1280x800 accel=kvm tafel=nein pins=terminal,explorer progs="$PROGS" \
        extra="$3" drehbuch="$2" > "$TMPD/$1/o.log" 2>&1 )
}

PPM_PY='
import sys
def load(p):
    d = open(p, "rb").read(); f = []; at = 2
    while len(f) < 3:
        while d[at:at+1].isspace(): at += 1
        s = at
        while not d[at:at+1].isspace(): at += 1
        f.append(int(d[s:at]))
    return f[0], d[at+1:]
'
barstat() { # <ppm> <x> <y> <w> <h> -> distinct colours in the rectangle
    python3 -I -c "$PPM_PY
W, a = load(sys.argv[1])
x0, y0, w, h = (int(v) for v in sys.argv[2:6])
c = set()
for y in range(y0, y0 + h):
    o = (y * W + x0) * 3
    for x in range(w):
        c.add(a[o + x*3:o + x*3 + 3])
print(len(c))
" "$@"
}
diffpix() { # <a.ppm> <b.ppm> <x> <y> <w> <h>
    python3 -I -c "$PPM_PY
W, a = load(sys.argv[1]); _, b = load(sys.argv[2])
x0, y0, w, h = (int(v) for v in sys.argv[3:7])
n = 0
for y in range(y0, y0 + h):
    o = (y * W + x0) * 3
    if a[o:o + w * 3] != b[o:o + w * 3]:
        for x in range(w):
            if a[o + x*3:o + x*3 + 3] != b[o + x*3:o + x*3 + 3]:
                n += 1
print(n)
" "$@"
}
field() { # <line> <key> -> number after key=
    echo "$1" | grep -a -o " $2=[0-9]*" | head -1 | cut -d= -f2
}

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
run_one a "$TMPD/dreh_a.txt" "tbkill=3000" &
run_one b "$TMPD/dreh_b.txt" "tbkill=3000 nosup" &
wait
SA="$TMPD/a/o/serial.txt"; SB="$TMPD/b/o/serial.txt"
if [ -n "${SHELLSUP_OUT:-}" ]; then
    mkdir -p "$SHELLSUP_OUT"
    for r in a b; do
        cp "$TMPD/$r/o/serial.txt" "$SHELLSUP_OUT/serial-$r.txt" 2>/dev/null
        for f in 00-before 01-after; do cp "$TMPD/$r/o/$f.ppm" "$SHELLSUP_OUT/$r-$f.ppm" 2>/dev/null; done
    done
fi
for r in a b; do
    if [ ! -s "$TMPD/$r/o/01-after.ppm" ]; then
        bad "run $r: no pictures: $(tail -n 3 "$TMPD/$r/o.log" | tr '\n' ' ')"
    fi
done
if [ "$fail" -gt 0 ]; then echo "SHELLSUP: $pass passed, $fail failed"; exit 1; fi

nh=$(grep -ac '^taskbar: health ' "$SA")
[ "$nh" = 2 ] && ok "A: two health lines (start + respawn)" || bad "A: expected 2 health lines, found $nh"
hl=$(grep -a '^taskbar: health ' "$SA" | head -1)
p1=$(field "taskbar: $hl" pins); [ -z "$p1" ] && p1=$(echo "$hl" | grep -a -o 'pins=[0-9]*' | cut -d= -f2)
[ -n "$p1" ] && [ "$p1" -ge 1 ] && ok "A: health line has pins=$p1" || bad "A: health pins missing: $hl"
p2=$(field "$hl" paints)
[ -n "$p2" ] && [ "$p2" -ge 1 ] && ok "A: health line has paints=$p2" || bad "A: health paints missing: $hl"
grep -aq '^desk: shell taskbar killed by hook' "$SA" && ok "A: hook killed the taskbar" || bad "A: no kill line"
grep -aq '^desk: shell taskbar ended slot=' "$SA" && ok "A: supervisor saw the end" || bad "A: no 'ended' line"
rl=$(grep -a '^desk: shell taskbar respawn pid=' "$SA" | head -1)
gap=$(field "$rl" gap)
[ -n "$gap" ] && [ "$gap" -le 150 ] && ok "A: respawn gap $gap ticks (<= 150)" || bad "A: respawn gap '$gap' missing or > 150: $rl"
kt=$(field "$(grep -a '^desk: shell taskbar killed by hook' "$SA" | head -1)" t)
hm=$(field "$(grep -a '^taskbar: health ' "$SA" | tail -1)" mono)
first=$(field "$hl" mono)
if [ -n "$kt" ] && [ -n "$hm" ] && [ -n "$first" ]; then
    back=$((hm - kt * 10))
    [ "$back" -lt 3000 ] && [ "$hm" -gt "$first" ] && ok "A: bar back ${back} ms after the kill (< 3000)" || bad "A: bar back after ${back} ms (kill t=$kt ticks, health mono=$hm)"
else
    bad "A: no kill tick or no health time"
fi
grep -aiqE 'panic|kernel fault|exception' "$SA" && bad "A: panic/fault on the serial line" || ok "A: 0 panics"
gm=$(grep -a -m1 '^taskbar: geom ' "$SA")
bx=$(field "$gm" x); by=$(field "$gm" y); bw=$(field "$gm" w); bh=$(field "$gm" h)
if [ -z "$bx" ] || [ -z "$bw" ]; then
    bad "A: no bar geometry"; bx=0; by=760; bw=1280; bh=40
fi
lw=$((bw * 6 / 10))
c0=$(barstat "$TMPD/a/o/00-before.ppm" "$bx" "$by" "$lw" "$bh")
[ "$c0" -ge 6 ] && ok "A: bar content before the kill: $c0 colours" || bad "A: bar looks empty before the kill ($c0 colours)"
d=$(diffpix "$TMPD/a/o/00-before.ppm" "$TMPD/a/o/01-after.ppm" "$bx" "$by" "$lw" "$bh")
[ "$d" -le $((lw * bh / 50)) ] && ok "A: bar after the respawn equals the one before ($d of $((lw * bh)) pixels differ)" \
    || bad "A: bar after the respawn differs in $d of $((lw * bh)) pixels"
nb=$(grep -ac '^taskbar: health ' "$SB")
[ "$nb" = 1 ] && ok "B control: one health line only (no respawn)" || bad "B control: expected 1 health line, found $nb"
grep -aq '^desk: shell taskbar respawn' "$SB" && bad "B control: respawned although nosup" || ok "B control: no respawn line"
db=$(diffpix "$TMPD/b/o/00-before.ppm" "$TMPD/b/o/01-after.ppm" "$bx" "$by" "$lw" "$bh")
[ "$db" -gt $((lw * bh / 4)) ] && ok "B control: bar gone from the picture ($db of $((lw * bh)) pixels differ)" \
    || bad "B control: only $db pixels differ -- the pixel check does not see a missing bar"
echo; echo "SHELLSUP: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
