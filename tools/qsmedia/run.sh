#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

BASE="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat orientbus act"

px() {
    python3 -I tools/qsmedia/px.py "$1" "$2" "$3"
}

cat > "$TMPD/dreh.txt" <<'DEOF'
warteauf 'launcher: ready' || 120
warte 6
klick 300,200
warte 1
tippe act call media.publish title=Demo-Song state=playing artist=Tester app=Demo can_prev=1 can_next=1
taste ret
warte 4
tippe act call media.current
taste ret
warte 3
taste meta_l-a
warteauf 'qs: open' || 30
warte 3
foto 01-open
klickauf qsmplay
warte 3
taste esc
warte 2
klick 300,200
warte 1
tippe act call media.poll app=Demo
taste ret
warte 4
foto 02-poll-toggle
taste meta_l-a
warte 3
klickauf qsmnext
warte 3
taste esc
warte 2
klick 300,200
warte 1
tippe act call media.poll app=Demo
taste ret
warte 4
foto 03-poll-next
taste meta_l-a
warte 3
klickauf qsmprev
warte 3
taste esc
warte 2
klick 300,200
warte 1
tippe act call media.poll app=Demo
taste ret
warte 4
foto 04-poll-prev
tippe act call media.publish title=Demo-Song state=paused artist=Tester app=Demo can_prev=1 can_next=1
taste ret
warte 4
taste meta_l-a
warte 3
foto 05-paused
taste esc
warte 2
klick 300,200
warte 1
tippe act call media.control cmd=pause owner=user:Ghost
taste ret
warte 4
tippe act call media.end app=Demo
taste ret
warte 4
foto 06-ended
taste meta_l-a
warte 3
foto 07-gone
taste esc
warte 2
DEOF

run_variant() {
    local name=$1 progs=$2
    local D="$TMPD/$name"
    for try in 1 2; do
        rm -rf "$D"
        bash tools/design/eh6.sh "$D" res=1280x800 accel=kvm progs="$progs" drehbuch="$TMPD/dreh.txt" > "$TMPD/$name.log" 2>&1
        grep -aq 'qs: open ' "$D/serial.txt" 2>/dev/null && break
    done
    if [ -n "${QSMEDIA_OUT:-}" ]; then
        mkdir -p "$QSMEDIA_OUT/$name"; cp "$D"/*.ppm "$D/serial.txt" "$TMPD/$name.log" "$QSMEDIA_OUT/$name/" 2>/dev/null
    fi
}

echo "== 1. with mediad =="
run_variant with "$BASE mediad"
S="$TMPD/with/serial.txt"
if [ ! -s "$TMPD/with/07-gone.ppm" ]; then
    bad "no pictures: $(tail -n 3 "$TMPD/with.log" | tr '\n' ' ')"
    echo "QSMEDIA: $pass passed, $fail failed"; exit 1
fi
for w in mprev mplay mnext; do
    if grep -aqE "qs: $w +x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+" "$S"; then ok "the card reports its $w button"; else bad "no 'qs: $w' report"; fi
done
for k in 26 27 28; do
    if grep -aqE "qs: media key=$k rc=1" "$S"; then ok "a click on key $k reached mediad (rc=1)"; else bad "no 'qs: media key=$k rc=1'"; fi
done
for c in toggle next prev; do
    if grep -aqE "wm: tw[0-9]+ [0-9]+ \[.*cmd=$c" "$S"; then ok "the player polled cmd=$c"; else bad "poll never showed cmd=$c"; fi
done
if grep -aqE "wm: tw[0-9]+ [0-9]+ \[.*Demo-Song" "$S"; then ok "media.current names the session"; else bad "media.current did not show Demo-Song"; fi
if grep -aqE "wm: tw[0-9]+ [0-9]+ \[.*err" "$S"; then ok "control for a session that does not exist is refused"; else bad "control for a ghost owner was not refused"; fi
nplay=$(grep -aoE 'qs: mplay +x=' "$S" | wc -l)
nopen=$(grep -aoE 'qs: open ' "$S" | wc -l)
if [ "$nopen" -ge 5 ] && [ "$nplay" -ge 4 ] && [ "$nplay" -lt "$nopen" ]; then
    ok "the card is there while the session lives ($nplay of $nopen openings) and gone after media.end"
else
    bad "card openings: $nplay of $nopen"
fi
geo=$(grep -aoE 'qs: geo x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+' "$S" | awk -F'[= ]' '$8 < 1000')
mp=$(grep -aoE 'qs: mplay +x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+' "$S" | head -1)
g1=$(echo "$geo" | head -1)
if [ -n "$mp" ] && [ -n "$g1" ]; then
    mx=$(echo "$mp" | sed -E 's/.* x=([0-9]+).*/\1/'); my=$(echo "$mp" | sed -E 's/.* y=([0-9]+).*/\1/')
    mw=$(echo "$mp" | sed -E 's/.* w=([0-9]+).*/\1/'); mh=$(echo "$mp" | sed -E 's/.* h=([0-9]+).*/\1/')
    gx=$(echo "$g1" | sed -E 's/.* x=([0-9]+).*/\1/'); gy=$(echo "$g1" | sed -E 's/.* y=([0-9]+).*/\1/')
    cx=$((gx + mx + mw / 2)); cy=$((gy + my + mh / 2))
    a=$(px "$TMPD/with/01-open.ppm" "$cx" "$cy"); b=$(px "$TMPD/with/05-paused.ppm" "$cx" "$cy")
    if [ "$a" != "$b" ]; then ok "the play button changes its glyph with the state ($a -> $b)"; else bad "play button looks the same playing and paused ($a)"; fi
else
    bad "no geometry for the pixel check"
fi
if grep -aqE 'panic|EXCEPTION' "$S"; then bad "a panic or exception"; else ok "no panic, no exception"; fi

echo "== 2. counter-proof: no mediad in the image =="
run_variant without "$BASE"
S2="$TMPD/without/serial.txt"
if [ ! -s "$TMPD/without/07-gone.ppm" ]; then
    bad "counter-proof run has no pictures"
else
    if grep -aqE 'qs: mplay +x=' "$S2"; then bad "the card appeared without mediad"; else ok "without mediad no media card appears"; fi
    if grep -aqE 'qs: media key=2[678] rc=1' "$S2"; then bad "a media click succeeded without mediad"; else ok "without mediad no media click succeeds"; fi
fi
echo; echo "QSMEDIA: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
