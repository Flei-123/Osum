#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
PASS=0; FAIL=0
ok()  { echo "  OK    $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
RES=1920x1080
HEX150=$(python3 -I tools/fracscale/edid.py 293 165)
HEX100=$(python3 -I tools/fracscale/edid.py 488 275)
HEX200=$(python3 -I tools/fracscale/edid.py 250 140)
cat > "$T/bar.conf" <<'CONF'
edge=bottom
height=48
width=104
autohide=0
ontop=1
align=center
labels=never
clock_lines=2
clock_date=1
clock_year4=1
pins=explorer,calc,settings,zip
CONF
mach() {
    local d=$1; shift
    bash tools/alltag/build.sh "$d" tbconf="$T/bar.conf" accel=$ACC uitrace=yes res=$RES "$@" > "$d.log" 2>&1
    [ -s "$d/desktop.png" ] || bash tools/alltag/build.sh "$d" tbconf="$T/bar.conf" accel=$ACC uitrace=yes res=$RES "$@" > "$d.log" 2>&1
}
mach "$T/a" extra="edid=$HEX150"
mach "$T/b" extra="edid=$HEX100"
mach "$T/c"
mach "$T/d" extra="edid=$HEX200"
A="$T/a/serial.txt"; B="$T/b/serial.txt"; C="$T/c/serial.txt"; D="$T/d/serial.txt"
for f in "$A" "$B" "$C" "$D"; do [ -s "$f" ] || { bad "no serial output: $f"; echo "FRACSCALE: $PASS passed, $FAIL failed"; exit 1; }; done
echo "== A. EDID 293x165 mm on 1920x1080 without virtio-gpu"
grep -aqE 'fb: skala x1 .* mm=290 +pct=150' "$A" && ok "kernel picks 150 percent (integer scale 1)" || bad "scale line: $(grep -a 'fb: skala' "$A" | head -1)"
grep -aqE 'taskbar: geom .* h=72 ' "$A" && ok "taskbar is 72 px high (48 pt at 150 percent)" || bad "taskbar geom: $(grep -a 'taskbar: geom ' "$A" | tail -1)"
grep -aqE 'taskbar: pin explorer .* w=60 h=60 ' "$A" && ok "pin buttons are 60x60 (40 pt at 150 percent)" || bad "pin: $(grep -a 'taskbar: pin explorer ' "$A" | head -1)"
grep -aqE 'fb: fonts pct=150 px_ui=23 px_mono=24' "$A" && ok "terminal font is 24 px (1.5 x 16) at 150 percent" || bad "fonts line 150: $(grep -a 'fb: fonts' "$A" | head -1)"
grep -aqE 'fb: fonts pct=100 px_ui=15 px_mono=16' "$B" && ok "terminal font stays 16 px at 100 percent" || bad "fonts line 100: $(grep -a 'fb: fonts' "$B" | head -1)"
grep -aqE 'fb: fonts pct=200 px_ui=30 px_mono=32' "$D" && ok "terminal font is 32 px at 200 percent" || bad "fonts line 200: $(grep -a 'fb: fonts' "$D" | head -1)"
echo "== B. thresholds and counter-proofs"
grep -aqE 'fb: skala x1 .* pct=100' "$B" && grep -aqE 'taskbar: geom .* h=48 ' "$B" && ok "100 dpi panel stays at 100 percent (bar 48 px)" || bad "100 dpi: $(grep -a 'fb: skala' "$B" | head -1) $(grep -a 'taskbar: geom ' "$B" | tail -1)"
grep -aqE 'taskbar: geom .* h=48 ' "$C" && ok "no boot EDID: bar stays 48 px (100 percent)" || bad "no EDID: $(grep -a 'taskbar: geom ' "$C" | tail -1)"
grep -aqE 'fb: skala x2 .* pct=200' "$D" && grep -aqE 'taskbar: geom .* h=96 ' "$D" && ok "250x140 mm panel gives 200 percent, bar 96 px" || bad "200 percent: $(grep -a 'fb: skala' "$D" | head -1) $(grep -a 'taskbar: geom ' "$D" | tail -1)"
grep -aq 'panic\|FAULT\|#UD\|#PF' "$A" && bad "kernel fault in the 150 percent run" || ok "no fault in the 150 percent run"
echo "== C. the picture"
if [ -s "$T/a/desktop.png" ] && [ -s "$T/c/desktop.png" ]; then
    mkdir -p docs/shots/fracscale; cp "$T/a/desktop.png" docs/shots/fracscale/desktop150.png
    sz=$(python3 -I -c "from PIL import Image; print(Image.open('$T/a/desktop.png').size)")
    [ "$sz" = "(1920, 1080)" ] && ok "screenshot is 1920x1080" || bad "screenshot size $sz"
    s150=$(python3 -I tools/fracscale/sharp.py "$T/a/desktop.png" 1650 1020 1900 1075)
    s100=$(python3 -I tools/fracscale/sharp.py "$T/c/desktop.png" 1650 1040 1900 1075)
    echo "        edge sharpness: 150 percent $s150, 100 percent $s100"
    python3 -I -c "import sys; sys.exit(0 if float('$s150') >= 0.8 * float('$s100') and float('$s150') > 0 else 1)" && ok "text edges at 150 percent as sharp as at 100 percent" || bad "blurred text at 150 percent ($s150 vs $s100)"
else bad "no screenshots"; fi
echo "FRACSCALE: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
