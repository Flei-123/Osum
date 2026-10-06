#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/win11bar/run.sh -- r384: THE TASKBAR IN THE LAYOUT OF WINDOWS 11.
#
#   bash tools/win11bar/run.sh
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
echo
echo "WIN11BAR: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
