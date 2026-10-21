#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/stab/report-test.sh -- host test of tools/stab/report.py (STAB-1), no VM, a few seconds.
#   bash tools/stab/report-test.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
chk() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
GOOD='desk: start /bin/taskbar  pid=3  kern=0
taskbar: STEHT x=0 y=752 w=1280 h=48
taskbar: icons=4 marks=3 sys=1 dateien=8 kleinste=588
taskbar: conf edge=0 ename=bottom height=48 width=104 autohide=0 ontop=1 align=center src=file
taskbar: ready ascent=11
taskbar: health pins=4 w=1280 h=48 paints=3 mono=1200'
printf '%s\n' "$GOOD" > "$D/test.txt"
# 1. identical boots: bar up, everything same, no differing line
cp "$D/test.txt" "$D/boss1.txt"
python3 -I tools/stab/report.py --boss "$D/boss1.txt" --test "$D/test.txt" --out "$D/r1.md" > /dev/null
chk "$D/r1.md" "- bar up: YES" "identical boots: bar up"
chk "$D/r1.md" "no blank bar reproduced" "identical boots: verdict says not reproduced"
# 2. boss never reaches ready/STEHT
grep -a "^desk:" "$D/test.txt" > "$D/boss2.txt"
python3 -I tools/stab/report.py --boss "$D/boss2.txt" --test "$D/test.txt" --out "$D/r2.md" > /dev/null
chk "$D/r2.md" "never got to ready/STEHT" "no ready: verdict names a dead/hung taskbar"
# 3. boss has a different conf (counter-proof: the class is named)
sed 's/height=48/height=0/' "$D/test.txt" | sed 's/pins=4/pins=0/' > "$D/boss3.txt"
python3 -I tools/stab/report.py --boss "$D/boss3.txt" --test "$D/test.txt" --out "$D/r3.md" > /dev/null
chk "$D/r3.md" "- bar up: NO" "pins=0: bar counted as not up"
chk "$D/r3.md" "boss differs in conf: height" "different conf height is the verdict"
# 4. geometry differs only in STEHT w
sed 's/STEHT x=0 y=752 w=1280/STEHT x=0 y=752 w=800/;s/pins=4/pins=0/' "$D/test.txt" > "$D/boss4.txt"
python3 -I tools/stab/report.py --boss "$D/boss4.txt" --test "$D/test.txt" --out "$D/r4.md" > /dev/null
chk "$D/r4.md" "boss differs in geometry: w" "different STEHT width is the verdict"
# 5. everything same but pins=0 and no conf difference -> conf/geometry/icons ruled out
sed 's/pins=4/pins=0/' "$D/test.txt" > "$D/boss5.txt"
python3 -I tools/stab/report.py --boss "$D/boss5.txt" --test "$D/test.txt" --out "$D/r5.md" > /dev/null
chk "$D/r5.md" "conf, geometry and icons ruled out" "pins=0 with equal conf/geometry/icons rules those out"
# 6. unreadable log
python3 -I tools/stab/report.py --boss "$D/none" --test "$D/test.txt" > /dev/null 2>&1; [ $? = 2 ] && ok "missing log: exit 2" || bad "missing log: exit code"
echo "stabreport: $pass/$fail OK/FAIL"
[ "$fail" = 0 ]
