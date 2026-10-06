#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/win11bar/run.sh -- r384: THE TASKBAR IN THE LAYOUT OF WINDOWS 11.
#
#   bash tools/win11bar/run.sh
#
# r387 (the rest of the layout): task view button, tray chevron, network/sound/battery as
# one capsule, a count on a pinned program -- sections D to F below.
#
# Reference: assets/ref/ (Justin's Windows 11 bar). What this measures, on the
# real taskbar in a VM (KVM when there is one), measured from the bar's own
# `taskbar:` trace lines and a photo:
#   * the pinned apps sit CENTRED (align=center), without labels (labels=never)
#   * the running program carries the small strip under its icon (photo)
#   * the language field "DEU" over "DE" is there (tray_language=1) -- and is NOT
#     there with the default conf (the counter-proof: no existing bar moves)
#   * the clock is two lines, time over date, with a FOUR digit year
#   * with the default conf the clock keeps its two digit year
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
PASS=0; FAIL=0
ok()  { echo "  OK    $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
cat > "$T/win11.conf" <<'CONF'
# taskbar.conf -- the Windows 11 layout (r384)
edge=bottom
height=40
width=104
autohide=0
ontop=1
align=center
labels=never
clock_lines=2
clock_date=1
clock_weekday=0
clock_year4=1
tray_language=1
pins=explorer,calc,settings,zip
CONF
bash tools/alltag/build.sh "$T/w" tbconf="$T/win11.conf" accel=$ACC uitrace=yes mode=dark scheme=night > "$T/w.log" 2>&1
bash tools/alltag/build.sh "$T/d" accel=$ACC uitrace=yes > "$T/d.log" 2>&1
W="$T/w/serial.txt"; D="$T/d/serial.txt"
[ -s "$W" ] && [ -s "$D" ] && ok "both machines ran" || { bad "no serial output"; echo "WIN11BAR: $PASS passed, $FAIL failed"; exit 1; }
echo "== A. the Windows 11 conf"
n=$(grep -ac 'taskbar: pin ' "$W"); [ "$n" -ge 4 ] && ok "four pinned apps in the bar ($n lines)" || bad "pins: $n"
px=$(grep -a 'taskbar: pin ' "$W" | head -4 | sed 's/.* x=\([0-9]*\) .*/\1/' | tr '\n' ' ')
set -- $px
first=$1; last=$4
mid=$(( (first + last + 32) / 2 ))
d=$(( mid > 640 ? mid - 640 : 640 - mid ))
[ "$d" -le 80 ] && ok "the pins sit around the middle of the 1280 wide screen (centre $mid)" || bad "pins not centred: centre $mid ($px)"
grep -aq 'taskbar: text button .* tw=0 ' "$W" && ok "labels=never: the running program has no text (symbol only)" || bad "a label is painted"
grep -aq 'taskbar: field lang .* lines=2' "$W" && ok "the language field is there, two lines" || bad "no language field"
grep -aq 'taskbar: text lang .* t=DEU' "$W" && grep -aq 'taskbar: text lang .* t=DE$' "$W" && ok "it says DEU over DE" || bad "wrong language text"
grep -aq 'taskbar: text clock .* t=[0-9][0-9]:[0-9][0-9]$' "$W" && grep -aqE 'taskbar: text clock .* t=[0-9]{2}\.[0-9]{2}\.[0-9]{4}$' "$W" \
    && ok "clock: time over date, four digit year" || bad "clock text"
echo "== B. COUNTER-PROOF: the default conf"
grep -aq 'taskbar: field lang' "$D" && bad "the default bar has a language field" || ok "no language field without tray_language=1"
grep -aqE 'taskbar: text clock .* t=[0-9]{2}:[0-9]{2}$' "$D" && ok "the default clock is one line, time only" || bad "default clock changed"
grep -aqE 'taskbar: text clock .* t=[0-9]{2}\.[0-9]{2}\.[0-9]{4}$' "$D" && bad "default bar shows a four digit year" || ok "no four digit year by default"
echo "== C. the picture"
if [ -s "$T/w/desktop.png" ]; then
    mkdir -p docs/shots/win11bar; cp "$T/w/desktop.png" docs/shots/win11bar/desktop.png
    python3 - "$T/w/desktop.png" <<'PY' && ok "the running program's strip (accent) sits under its icon in the photo" || bad "no strip under the running icon"
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB'); w, h = im.size
found = 0
for y in range(h - 12, h):
    for x in range(500, 800):
        r, g, b = im.getpixel((x, y))
        if g > 200 and r < 150 and b < 200:   # the accent strip of the dark bar
            found += 1
sys.exit(0 if found >= 8 else 1)
PY
else bad "no photo"; fi

# a machine whose screenshot step timed out under load is run once more
mach() { bash tools/alltag/build.sh "$@"; [ -s "$1/desktop.png" ] || bash tools/alltag/build.sh "$@"; }
echo "== D. the rest of the Windows 11 layout (task view, chevron, capsule, count)"
cat > "$T/win11b.conf" <<'CONF'
# taskbar.conf -- the Windows 11 layout, rest (r387)
edge=bottom
height=40
width=104
autohide=0
ontop=1
align=center
labels=never
clock_lines=2
clock_date=1
clock_weekday=0
clock_year4=1
tray_language=1
taskview=1
tray_chevron=1
tray_group=1
badges=1
pins=explorer,calc,settings,zip
CONF
mach "$T/b0" tbconf="$T/win11b.conf" accel=$ACC uitrace=yes mode=dark scheme=night > "$T/b0.log" 2>&1
B0="$T/b0/serial.txt"
field() { grep -a "^taskbar: $1 " "$2" | tail -1 | grep -oE "$3=[0-9]+" | tail -1 | cut -d= -f2; }
tvx=$(field taskview "$B0" x); tvw=$(field taskview "$B0" w); stx=$(field start "$B0" x); stw=$(field start "$B0" w)
chx=$(field chevron "$B0" x); chw=$(field chevron "$B0" w); lgx=$(field "field lang" "$B0" x)
gx=$(field group "$B0" x); gw=$(field group "$B0" w); nx=$(field "field net" "$B0" x); nw=$(field "field net" "$B0" w)
p1=$(grep -a '^taskbar: pin ' "$B0" | head -1 | sed 's/.* x=\([0-9]*\) .*/\1/')
[ -n "$tvx" ] && [ "${tvw:-0}" -ge 32 ] && ok "the task view button is there ($tvw wide at $tvx)" || bad "no task view button ($tvx/$tvw)"
[ -n "$tvx" ] && [ "$tvx" -ge $((stx + stw)) ] && [ "${p1:-0}" -ge $((tvx + tvw)) ] \
    && ok "it sits between the start button and the first pin ($stx+$stw <= $tvx, pin at $p1)" || bad "task view button misplaced ($stx $stw / $tvx $tvw / pin $p1)"
[ -n "$chx" ] && [ "$((chx + chw))" -le "${lgx:-0}" ] && ok "the chevron is the leftmost thing of the tray (ends at $((chx + chw)), language at $lgx)" || bad "chevron misplaced ($chx $chw / lang $lgx)"
[ -n "$gx" ] && [ "$gx" -le "${nx:-0}" ] && [ "$((nx + nw))" -le "$((gx + gw))" ] && ok "the network field sits inside the capsule ($gx..$((gx + gw)) holds $nx..$((nx + nw)))" || bad "no capsule around the network field ($gx $gw / $nx $nw)"
echo "== D2. COUNTER-PROOF: the default conf has none of it"
for w in "taskbar: taskview" "taskbar: chevron" "taskbar: group" "taskbar: badge"; do
    grep -aq "$w" "$D" && bad "the default bar has a line '$w'" || ok "no '$w' by default"
done
echo "== E. the count on a pinned program, and the chevron"
fieldline() { grep -a "^taskbar: $1 " "$2" | tail -1; }
exy=$(grep -a '^taskbar: pin explorer ' "$B0" | head -1)
ex=$(echo "$exy" | sed 's/.* x=\([0-9]*\) .*/\1/'); ey=$(echo "$exy" | sed 's/.* y=\([0-9]*\) .*/\1/')
ew=$(echo "$exy" | sed 's/.* w=\([0-9]*\) .*/\1/'); eh=$(echo "$exy" | sed 's/.* h=\([0-9]*\) .*/\1/')
BARY=$(grep -a '^taskbar: geom ' "$B0" | tail -1 | grep -oE ' y=[0-9]+' | tail -1 | cut -d= -f2)
echo "        bar y=$BARY, explorer pin $ex,$ey ${ew}x$eh"
mach "$T/b1" tbconf="$T/win11b.conf" accel=$ACC uitrace=yes mode=dark scheme=night extra="wighalt=45" click=$((ex + ew / 2)),$((BARY + ey + eh / 2)) warten=16 > "$T/b1.log" 2>&1 &
P1=$!
mach "$T/b2" tbconf="$T/win11b.conf" accel=$ACC uitrace=yes mode=dark scheme=night click=$((chx + chw / 2)),$((BARY + 20)) click=$((tvx + tvw / 2)),$((BARY + 20)) warten=3 > "$T/b2.log" 2>&1 &
P2=$!
wait $P1 $P2
B1="$T/b1/serial.txt"; B2="$T/b2/serial.txt"
grep -aq 'taskbar: pin starte /apps/explorer.osp/start' "$B1" && ok "a click on the pin starts the program" || bad "the pin did not start the program"
grep -aqE 'taskbar: badge txt=1 n=1 ' "$B1" && ok "the running pinned program carries a count (badges=1: one window is enough)" || bad "no count on the pin"
grep -aq 'taskbar: badge' "$B0" && bad "a count before anything runs" || ok "no count while nothing of it runs"
grep -aq 'taskbar: click .* hits=chevron' "$B2" && grep -aqE 'taskbar: chevron .* open=1' "$B2" && ok "a click on the chevron opens the tray (open=0 -> open=1)" || bad "the chevron did not open"
grep -aq 'taskbar: click .* hits=taskview' "$B2" && grep -aqE 'taskview: open n=[1-9]' "$B2" && grep -aqE 'taskview: row 0 id=[0-9]+ title=.+' "$B2" \
    && ok "a click on the task view button opens the card with the windows ($(grep -a 'taskview: open' "$B2" | tail -1))" || bad "the task view card did not open"
echo "== F. the pictures"
python3 - "$T/b0/desktop.png" "$T/b1/desktop.png" "$T/b2/desktop.png" "$T" "$B1" "$B2" <<'PY' && ok "badge in the photo, card in the photo (and only there)" || bad "pictures do not show the badge / the card"
import re, sys
from PIL import Image
p0, p1, p2, T, s1, s2 = sys.argv[1:7]
a, b, c = (Image.open(x).convert('RGB') for x in (p0, p1, p2))
bl = [l for l in open(s1, errors='replace') if l.startswith('taskbar: badge txt=')]
m = re.search(r' x=(\d+) y=(\d+) w=(\d+) h=(\d+)', bl[-1]); bx, by, bw, bh = (int(v) for v in m.groups())
BARY = int(re.findall(r' y=(\d+)', [l for l in open(s1, errors='replace') if l.startswith('taskbar: geom ')][-1])[-1])
def bright(im, x0, y0, w, h):
    n = 0
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            r, g, bb = im.getpixel((x, y))
            if g > 150 or r > 150: n += 1
    return n
withb = bright(b, bx, BARY + by, bw, bh); without = bright(a, bx, BARY + by, bw, bh)
print("badge area bright pixels: with %d without %d" % (withb, without))
ok1 = withb >= 40 and without <= 8
ol = [l for l in open(s2, errors='replace') if l.startswith('taskview: open')]
m = re.search(r' x=(\d+) y=(\d+) w=(\d+) h=(\d+)', ol[-1]); cx, cy, cw, ch = (int(v) for v in m.groups())
diff = 0
for y in range(cy, cy + ch):
    for x in range(cx, cx + cw):
        if sum(abs(u - v) for u, v in zip(a.getpixel((x, y)), c.getpixel((x, y)))) > 40: diff += 1
frac = 100.0 * diff / (cw * ch)
print("card area: %.1f %% of the pixels differ from the photo without it" % frac)
sys.exit(0 if ok1 and frac > 30 else 1)
PY
mkdir -p docs/shots/win11bar
[ -s "$T/b1/desktop.png" ] && cp "$T/b1/desktop.png" docs/shots/win11bar/badge.png
[ -s "$T/b2/desktop.png" ] && cp "$T/b2/desktop.png" docs/shots/win11bar/taskview.png
[ -s "$T/b0/desktop.png" ] && cp "$T/b0/desktop.png" docs/shots/win11bar/tray.png
echo
echo "WIN11BAR: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
