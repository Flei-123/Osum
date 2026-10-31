#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

cat > "$TMPD/click.txt" <<'EOF'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 8
foto 00-base
taste meta_l-a
warteauf 'qs: open' || 30
warte 2
klickauf qskachel7
warte 4
foto 01-on
klickauf qskachel7
warte 4
foto 02-off
taste esc
warte 2
EOF

cat > "$TMPD/idle.txt" <<'EOF'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 20
foto 00-base
EOF

printf '# /etc/modes.conf\nnight=true\nnight_strength=70\n' > "$TMPD/modes-night.conf"

mean() {
    python3 -I - "$1" <<'PY'
import sys
d = open(sys.argv[1], "rb").read()
f = []; at = 2
while len(f) < 3:
    while d[at:at+1].isspace(): at += 1
    s = at
    while not d[at:at+1].isspace(): at += 1
    f.append(int(d[s:at]))
at += 1
w, h, _ = f
sums = [0, 0, 0]; n = 0
for y in range(40, 240):
    row = at + (y * w + 40) * 3
    for x in range(200):
        o = row + x * 3
        sums[0] += d[o]; sums[1] += d[o+1]; sums[2] += d[o+2]; n += 1
print(sums[0] * 1000 // n, sums[1] * 1000 // n, sums[2] * 1000 // n)
PY
}

blue_share() {
    local r g b
    read -r r g b <<< "$(mean "$1")"
    echo $(( b * 1000 / (r + g + b + 1) ))
}

want() { [ -z "${QSMODES_ONLY:-}" ] || [[ " $QSMODES_ONLY " == *" $1 "* ]]; }
absdiff() { local d=$(( $1 - $2 )); [ "$d" -lt 0 ] && d=$(( -d )); echo "$d"; }

run_one() {
    local name=$1 script=$2 more=$3 etc=$4
    mkdir -p "$TMPD/$name"
    EH_MKFS_EXTRA="/var/ /var/log/" EH_ETC_EXTRA="$etc" DESIGNBUILD="$TMPD/$name/build" bash tools/design/eh6.sh "$TMPD/$name/o" res=1280x800 uiscale=1 mode=dark accel=kvm tafel=nein \
        "moreprogs=$more" drehbuch="$script" > "$TMPD/$name/o.log" 2>&1
    rm -rf "$TMPD/$name/build"
    if [ -n "${QSMODES_OUT:-}" ]; then
        mkdir -p "$QSMODES_OUT/$name"; cp "$TMPD/$name/o/serial.txt" "$TMPD/$name/o/"*.ppm "$QSMODES_OUT/$name/" 2>/dev/null
    fi
}

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

echo "== A: direct fallback (no bus), tile 7 on and off =="
A="$TMPD/a/o"
ba=0
want a && run_one a "$TMPD/click.txt" "" ""
if ! want a; then :; elif [ ! -s "$A/02-off.ppm" ]; then bad "A: no pictures"; else
    b0=$(blue_share "$A/00-base.ppm"); b1=$(blue_share "$A/01-on.ppm"); b2=$(blue_share "$A/02-off.ppm")
    ba=$b0
    if [ "$b1" -lt $((b0 - 15)) ]; then ok "A: night on lowers the blue share ($b0 -> $b1 per mille)"
    else bad "A: night on did not lower the blue share ($b0 -> $b1)"; fi
    if [ "$(absdiff "$b2" "$b0")" -le 5 ]; then ok "A: night off restores the blue share ($b0 -> $b2)"
    else bad "A: night off did not restore the blue share ($b0 -> $b2)"; fi
    r0=$(mean "$A/00-base.ppm" | cut -d' ' -f1); r1=$(mean "$A/01-on.ppm" | cut -d' ' -f1)
    if [ "$r1" -ge $((r0 * 90 / 100)) ]; then ok "A: red stays (>=90 %) while blue goes ($r0 -> $r1)"
    else bad "A: red dropped too much ($r0 -> $r1)"; fi
    if [ "$(grep -ac 'qs: tile n=7' "$A/serial.txt")" -ge 2 ]; then ok "A: both clicks reached the system (qs: tile n=7)"
    else bad "A: tile clicks missing in the serial log"; fi
fi

echo "== B: counter-proof, no click, no seed =="
B="$TMPD/b/o"
want bc && run_one b "$TMPD/idle.txt" "orientbus settingsd" ""
echo "== C: persistence, /etc/modes.conf night=true seeded, bus + settingsd =="
C="$TMPD/c/o"
want bc && run_one c "$TMPD/idle.txt" "orientbus settingsd" "/etc/modes.conf=$TMPD/modes-night.conf@0644"
if ! want bc; then :; elif [ ! -s "$B/00-base.ppm" ] || [ ! -s "$C/00-base.ppm" ]; then bad "B/C: no pictures"; else
    bb=$(blue_share "$B/00-base.ppm"); bc=$(blue_share "$C/00-base.ppm")
    if [ "$bc" -lt $((bb - 15)) ]; then ok "C: seeded night=true is applied after boot ($bb -> $bc per mille)"
    else bad "C: seeded night was not applied ($bb -> $bc)"; fi
    if [ "$ba" -gt 0 ] && [ "$(absdiff "$bb" "$ba")" -le 10 ]; then ok "B: without the seed the colour is untouched ($bb vs $ba)"
    else bad "B: unexpected colour without seed ($bb vs $ba)"; fi
fi

echo "== D: bus path, tile 7 on and off through settings.set =="
D="$TMPD/d/o"
want d && run_one d "$TMPD/click.txt" "orientbus settingsd" "${QSMODES_D_ETC:-}"
if ! want d; then :; elif [ ! -s "$D/02-off.ppm" ]; then bad "D: no pictures"; else
    d0=$(blue_share "$D/00-base.ppm"); d1=$(blue_share "$D/01-on.ppm"); d2=$(blue_share "$D/02-off.ppm")
    if [ "$d1" -lt $((d0 - 15)) ]; then ok "D: night on via the bus ($d0 -> $d1)"
    else bad "D: night on via the bus failed ($d0 -> $d1)"; fi
    if [ "$(absdiff "$d2" "$d0")" -le 5 ]; then ok "D: night off via the bus ($d0 -> $d2)"
    else bad "D: night off via the bus failed ($d0 -> $d2)"; fi
fi

echo; echo "QSMODES: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
