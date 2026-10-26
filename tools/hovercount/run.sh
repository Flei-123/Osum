#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
MAXCYC=${HOVERCOUNT_MAX_CYC:-2000}

cat > "$TMPD/a.txt" <<'EOT'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 8
fahre 100,100
warte 1
fahre 300,300
warte 1
fahre 600,200
warte 1
fahre 900,500
warte 1
fahre 400,600
warte 3
foto 00-end
EOT
cat > "$TMPD/b.txt" <<'EOT'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 8
foto 00-end
EOT
cat > "$TMPD/c.txt" <<'EOT'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 8
fahre 100,100
warte 1
fahre 600,300
warte 1
taste ctrl-shift-t
warte 6
tippe grep hover /proc/frames
taste ret
warte 3
foto 00-end
EOT

run_one() { # <name> <script> <extra>
    mkdir -p "$TMPD/$1"
    ( EH_MKFS_EXTRA="/proc/" DESIGNBUILD="$TMPD/$1/build" bash tools/design/eh6.sh "$TMPD/$1/o" res=1280x800 accel=kvm tafel=nein "moreprogs=term grep" "extra=vfs lang=en $3" \
        drehbuch="$2" > "$TMPD/$1/o.log" 2>&1 )
    rm -rf "$TMPD/$1/build"
}
field() { echo "$1" | grep -a -o " $2=[0-9]*" | head -1 | cut -d= -f2; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
run_one a "$TMPD/a.txt" "framesdump=300"
run_one b "$TMPD/b.txt" "framesdump=300"
run_one c "$TMPD/c.txt" ""
SA="$TMPD/a/o/serial.txt"; SB="$TMPD/b/o/serial.txt"
if [ -n "${HOVERCOUNT_OUT:-}" ]; then
    mkdir -p "$HOVERCOUNT_OUT"
    cp "$SA" "$HOVERCOUNT_OUT/serial-a.txt" 2>/dev/null; cp "$SB" "$HOVERCOUNT_OUT/serial-b.txt" 2>/dev/null
fi
[ -s "$SA" ] && [ -s "$SB" ] || { bad "no serial output: $(tail -n 3 "$TMPD/a/o.log" | tr '\n' ' ')"; echo "HOVERCOUNT: $pass passed, $fail failed"; exit 1; }

la=$(grep -a '^frames: hover' "$SA" | tail -1)
lb=$(grep -a '^frames: hover' "$SB" | tail -1)
[ -n "$la" ] && ok "A: hover line present" || bad "A: no 'frames: hover' line"
for k in in pushed popped; do
    v=$(field "$la" "$k")
    [ -n "$v" ] && [ "$v" -gt 0 ] && ok "A: $k=$v > 0" || bad "A: $k='$v' not > 0"
done
ia=$(field "$la" in); pa=$(field "$la" pushed); oa=$(field "$la" popped); wa=$(field "$la" win)
[ -n "$oa" ] && [ -n "$pa" ] && [ "$oa" -le "$pa" ] && ok "A: popped ($oa) <= pushed ($pa)" || bad "A: popped '$oa' vs pushed '$pa'"
[ -n "$wa" ] && [ "$wa" -gt 0 ] && ok "A: last target window recorded (win=$wa)" || bad "A: win='$wa'"
cyc=$(field "$(grep -a '^frames: total=' "$SA" | tail -1 | sed 's/total=/ total=/')" note_cyc)
[ -n "$cyc" ] && [ "$cyc" -le "$MAXCYC" ] && ok "A: frame counter cost $cyc cycles (<= $MAXCYC)" || bad "A: note_cyc '$cyc'"
ib=$(field "$lb" in)
echo "  INFO  A in=$ia pushed=$pa popped=$oa win=$wa / B in=${ib:-none}"
if [ -n "$lb" ]; then
    [ "$ib" -lt "$ia" ] && ok "B: without pointer moves in=$ib < A in=$ia (counter measures moves)" || bad "B: in=$ib not below A in=$ia"
else
    ok "B: no hover line without moves (counter measures moves)"
fi
python3 -I - "$TMPD/c/o/00-end.ppm" "$TMPD/c/crop.png" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("L")
im = im.resize((im.width * 2, im.height * 2))
im.save(sys.argv[2])
PY
txt=$(tesseract "$TMPD/c/crop.png" - 2>/dev/null | tr -s ' \n' ' ')
[ -n "${HOVERCOUNT_OUT:-}" ] && cp "$TMPD/c/o/00-end.ppm" "$HOVERCOUNT_OUT/c-end.ppm" 2>/dev/null
echo "$txt" | grep -qi "hover.in" && ok "C: /proc/frames shows frames.hover.in" || bad "C: frames.hover.in not on screen: $(echo "$txt" | cut -c1-200)"
echo "$txt" | grep -qi "hover.popped" && ok "C: /proc/frames shows frames.hover.popped" || bad "C: frames.hover.popped not on screen"
grep -aiqE 'panic|kernel fault|exception' "$SA" && bad "A: panic on the serial line" || ok "A: 0 panics"
echo "HOVERCOUNT: $pass passed, $fail failed"
[ "$fail" = 0 ]
