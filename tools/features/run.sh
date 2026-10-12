#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/features/run.sh -- EVERYDAY FEATURES, VM gate (docs/FEATURES-STAND.md).
#
#   bash tools/features/run.sh        (start it through /root/jarvis/bin/heavy)
#
# 1. NOTIFICATION CENTRE (kernel/user/notifc.fi), on the machine of the stick (tools/design/eh6.sh):
#      two `notify` posts in the terminal -> the bell (`taskbar: field noti`) -> a click on it opens
#      the card with both rows, newest first (`notifc: open n=2`, `row 0 ... second message`)
#      -> Tab + Enter on "Clear all" empties it (`notifc: clear n=2`, `open n=0`) -> Escape closes
#      -> a third post -> the bell comes back, its card lists ONLY the third (the base line works,
#      `open n=1`) -> a click on the bell closes it (`notifc: shut bell`).
#      The pictures 01-open / 02-cleared / 03-open2 differ from the bare desktop inside the card.
#
# Pictures go to $FEATURES_OUT when it is set.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify"

cat > "$TMPD/dreh.txt" <<'EOF'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 6
foto 00-before
klick 300,200
warte 2
taste ret
warte 1
tippe notify first message
taste ret
warte 2
tippe notify second message
taste ret
warte 3
klickauf glocke
warte 4
foto 01-open
taste tab
warte 1
taste ret
warte 3
foto 02-cleared
taste esc
warte 2
klick 300,200
warte 1
taste ret
tippe notify third message
taste ret
warte 4
klickauf glocke
warte 4
foto 03-open2
klickauf glocke
warte 3
foto 04-shut
EOF

bash tools/design/eh6.sh "$TMPD/o" res=1280x800 accel=kvm progs="$PROGS" \
    drehbuch="$TMPD/dreh.txt" > "$TMPD/o.log" 2>&1
S="$TMPD/o/serial.txt"
if [ -n "${FEATURES_OUT:-}" ]; then mkdir -p "$FEATURES_OUT"; cp "$TMPD"/o/*.ppm "$S" "$TMPD/o.log" "$FEATURES_OUT/" 2>/dev/null; fi
if [ ! -s "$TMPD/o/04-shut.ppm" ]; then
    bad "no pictures: $(tail -n 3 "$TMPD/o.log" | tr '\n' ' ')"
    echo "FEATURES: $pass passed, $fail failed"; exit 1
fi

# number of pixels that differ between two pictures inside a rectangle
diffpix() { # <a.ppm> <b.ppm> <x> <y> <w> <h>
    python3 - "$@" <<'PY'
import sys
def load(p):
    d = open(p, "rb").read(); f = []; at = 2
    while len(f) < 3:
        while d[at:at+1].isspace(): at += 1
        s = at
        while not d[at:at+1].isspace(): at += 1
        f.append(int(d[s:at]))
    return f[0], d[at+1:]
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
PY
}

echo "== notification centre =="
grep -qaF "taskbar: no notifc host" "$S" && bad "the bar had no room for the card" || ok "the card has its window (no 'no notifc host')"
grep -qaE 'taskbar: field noti ' "$S" && ok "the bell is on the bar once there is something unread" || bad "no bell field"
o1=$(grep -a 'notifc: open n=' "$S" | head -1)
echo "$o1" | grep -qaF "n=2" && ok "the click on the bell opens the card with 2 rows" || bad "first open is not n=2: '$o1'"
r0=$(grep -a 'notifc: row 0 ' "$S" | head -1); r1=$(grep -a 'notifc: row 1 ' "$S" | head -1)
echo "$r0" | grep -qaF "second message" && ok "row 0 is the newest (second message)" || bad "row 0 wrong: '$r0'"
echo "$r1" | grep -qaF "first message" && ok "row 1 is the older one (first message)" || bad "row 1 wrong: '$r1'"
# the card in the picture: the rectangle of 'notifc: open' differs from the bare desktop
tx=$(echo "$o1" | sed -E 's/.* x=([0-9]+).*/\1/'); ty=$(echo "$o1" | sed -E 's/.* y=([0-9]+).*/\1/')
tw=$(echo "$o1" | sed -E 's/.* w=([0-9]+).*/\1/'); th=$(echo "$o1" | sed -E 's/.* h=([0-9]+).*/\1/')
if [ -n "$tx" ] && [ -n "$tw" ] && [ "$tw" -gt 0 ] 2>/dev/null; then
    d=$(diffpix "$TMPD/o/00-before.ppm" "$TMPD/o/01-open.ppm" "$tx" "$ty" "$tw" "$th")
    [ "$d" -gt $((tw * th / 3)) ] && ok "the card is in the picture ($d of $((tw * th)) pixels differ from before)" \
        || bad "only $d of $((tw * th)) pixels differ -- no card in the picture"
else
    bad "no card rectangle in '$o1'"
fi
grep -qaF "notifc: clear n=2" "$S" && ok "Tab + Enter on 'Clear all' marked 2 entries read" || bad "no 'notifc: clear n=2'"
grep -aq 'notifc: open n=0' "$S" && ok "after clearing the list is empty" || bad "no empty list after clearing"
grep -qaF "notifc: shut esc" "$S" && ok "Escape closes the card" || bad "no 'notifc: shut esc'"
o3=$(grep -a 'notifc: open n=1' "$S" | tail -1)
[ -n "$o3" ] && ok "the card after the third post shows ONE row (the cleared two stay gone)" || bad "no 'open n=1' after the third post"
grep -a 'notifc: row 0 ' "$S" | tail -1 | grep -qaF "third message" && ok "that row is the third message" || bad "the last row 0 is not the third message"
grep -qaF "notifc: shut bell" "$S" && ok "a click on the bell closes the card again" || bad "no 'notifc: shut bell'"

# ---------------------------------------------------------------------------------------------------------------
# 2. DO NOT DISTURB (quick settings tile 6, kernel/user/qs.fi + the toast gate in taskbar.fi)
#    tile on -> a posted message still reaches the bell but raises NO toast; tile off -> the next one pops up.
cat > "$TMPD/dreh2.txt" <<'EOF'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 6
klick 300,200
warte 2
taste ret
warte 1
taste meta_l-a
warteauf 'qs: open' || 30
warte 2
klickauf qskachel6
warte 2
foto 10-dnd-on
taste esc
warte 2
klick 300,200
warte 1
taste ret
tippe notify muted message
taste ret
warte 5
foto 11-muted
taste meta_l-a
warteauf 'qs: open' || 30
warte 2
klickauf qskachel6
warte 2
taste esc
warte 2
klick 300,200
warte 1
taste ret
tippe notify loud message
taste ret
warte 5
foto 12-loud
EOF
bash tools/design/eh6.sh "$TMPD/d" res=1280x800 accel=kvm progs="$PROGS" \
    drehbuch="$TMPD/dreh2.txt" > "$TMPD/d.log" 2>&1
S2="$TMPD/d/serial.txt"
if [ -n "${FEATURES_OUT:-}" ]; then cp "$TMPD"/d/*.ppm "$S2" "$TMPD/d.log" "$FEATURES_OUT/" 2>/dev/null; fi
echo "== do not disturb =="
grep -aqE '^qs: kachel n=6 ' "$S2" && ok "the panel reports the do-not-disturb tile (n=6)" || bad "no 'qs: kachel n=6'"
grep -aqE '^qs: tile n=6 to=1 rc=0' "$S2" && ok "a click on the tile switches it on (to=1)" || bad "no 'qs: tile n=6 to=1 rc=0'"
grep -aqF 'qs: dnd = 1' "$S2" && ok "the switch reached the bar (qs: dnd = 1)" || bad "no 'qs: dnd = 1'"
if grep -a 'taskbar: toast \[' "$S2" | grep -aqF 'muted message'; then bad "a toast popped up for the muted message"; else ok "NO toast for the message posted while do-not-disturb was on"; fi
grep -aqE '^qs: tile n=6 to=0 rc=0' "$S2" && ok "the second click switches it off (to=0)" || bad "no 'qs: tile n=6 to=0 rc=0'"
if grep -a 'taskbar: toast \[' "$S2" | grep -aqF 'loud message'; then ok "counter-proof: with the tile off the next message does pop up"; else bad "counter-proof failed: no toast for the loud message"; fi

echo; echo "FEATURES: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
