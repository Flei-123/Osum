#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
KEEP=${PIXELGUARD_KEEP:-}
MIN_CHECKS=${PIXELGUARD_MIN_CHECKS:-150}
MAX_US=${PIXELGUARD_MAX_US:-400000}
PROBES=${PIXELGUARD_PROBES:-1 2 3 4 5}

section() { printf '== %s ==\n' "$1"; }
tally() {
    local rc=$1 name=$2
    if [ "$rc" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); fi
    printf '  %s: %s\n' "$name" "$([ "$rc" -eq 0 ] && echo green || echo RED)"
}

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
BUILD="$TMPD/build"

shoot() {
    local name=$1 plan=$2 extra=$3
    mkdir -p "$TMPD/$name"
    DESIGNBUILD="$BUILD" AUDIT_MEM=1024 bash tools/design/audit.sh "$TMPD/$name/o" accel=kvm uitrace=yes halt=400 \
        drehbuch="$plan" extra="$extra" > "$TMPD/$name/o.log" 2>&1
    if [ -n "$KEEP" ]; then
        mkdir -p "$KEEP/$name"
        cp "$TMPD/$name/o/serial.txt" "$KEEP/$name/" 2>/dev/null
        cp "$TMPD/$name/o/"*.png "$KEEP/$name/" 2>/dev/null
    fi
}

shoot_term() {
    local name=$1 plan=$2 extra=$3
    mkdir -p "$TMPD/$name"
    EH_MKFS_EXTRA="/proc/" DESIGNBUILD="$TMPD/$name/build" bash tools/design/eh6.sh "$TMPD/$name/o" res=1280x800 accel=kvm tafel=nein moreprogs=term \
        "extra=vfs lang=en $extra" drehbuch="$plan" > "$TMPD/$name/o.log" 2>&1
    rm -rf "$TMPD/$name/build"
    if [ -n "$KEEP" ]; then
        mkdir -p "$KEEP/$name"
        cp "$TMPD/$name/o/serial.txt" "$KEEP/$name/" 2>/dev/null
        cp "$TMPD/$name/o/"*.ppm "$KEEP/$name/" 2>/dev/null
    fi
}

section "1. clean run: every composed frame equals the reference render"
shoot clean tools/pixelguard/clean.txt "pixelguard=all"
if [ -s "$TMPD/clean/o/serial.txt" ]; then
    python3 -I tools/pixelguard/judge.py clean "$TMPD/clean/o/serial.txt" "$MIN_CHECKS" "$MAX_US"
    tally $? "clean"
else
    tally 1 "clean (no serial: $(tail -n 2 "$TMPD/clean/o.log" | tr '\n' ' '))"
fi

for n in $PROBES; do
    section "2.$n counter-probe pgbug=$n must be detected"
    shoot "bug$n" tools/pixelguard/bug.txt "pixelguard=all pgfreeze pgbug=$n"
    if [ -s "$TMPD/bug$n/o/serial.txt" ]; then
        python3 -I tools/pixelguard/judge.py probe "$n" "$TMPD/bug$n/o/serial.txt"
        tally $? "probe $n"
    else
        tally 1 "probe $n (no serial)"
    fi
done

section "3. Settings switch debug.pixelguard: on, off, on (boot without the word)"
cat > "$TMPD/switch.txt" <<'EOT'
warte 12
klick 24,780
warte 3
klickauf start_Settings
warte 12
klickauf srecttabp
warte 3
foto c-0
klickauf srectmpgd
warte 6
fahre 300,300
fahre 600,200
warte 3
taste f12
warte 2
klickauf srectmpgd
warte 4
klickauf srectmpgd
warte 6
fahre 300,300
fahre 600,200
warte 3
taste f12
warte 3
foto c-on2
EOT
shoot_term switch "$TMPD/switch.txt" ""
if [ -s "$TMPD/switch/o/serial.txt" ]; then
    python3 -I tools/pixelguard/judge.py switch "$TMPD/switch/o/serial.txt"
    tally $? "switch"
else
    tally 1 "switch (no serial)"
fi

section "4. /proc/frames shows frames.pixelguard.*"
cat > "$TMPD/proc.txt" <<'EOT'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 8
fahre 100,100
warte 1
fahre 600,300
warte 1
taste ctrl-shift-t
warte 6
tippe grep pixelguard /proc/frames
taste ret
warte 3
foto proc
EOT
shoot_term proc "$TMPD/proc.txt" "pixelguard=all"
python3 -I - "$TMPD/proc/o/proc.ppm" "$TMPD/proc/crop.png" <<'PY'
import sys
from PIL import Image, ImageOps
im = Image.open(sys.argv[1]).convert("L")
im = ImageOps.invert(im.crop((40, 140, 1180, 620)))
im.resize((im.width * 3, im.height * 3)).save(sys.argv[2])
PY
txt=$(tesseract "$TMPD/proc/crop.png" - --psm 6 2>/dev/null)
rc=0
for k in mode checks bad unstable pending skipped px card_checks card_bad x0 y0 x1 y1 win us renders; do
    if echo "$txt" | grep -qi "pixelguard\. *$k "; then
        :
    else
        printf '  FAIL  /proc/frames line frames.pixelguard.%s not readable on screen\n' "$k"
        rc=1
    fi
done
[ "$rc" -eq 0 ] && printf '  OK    all 16 frames.pixelguard.* lines are readable on screen\n'
mode=$(echo "$txt" | grep -i "pixelguard\. *mode " | head -1 | grep -o '[0-9]*$')
checks=$(echo "$txt" | grep -i "pixelguard\. *checks " | head -1 | grep -o '[0-9]*$')
[ "${mode:-}" = "2" ] && printf '  OK    frames.pixelguard.mode=2\n' || { printf '  FAIL  frames.pixelguard.mode=%s (want 2)\n' "${mode:-}"; rc=1; }
[ -n "${checks:-}" ] && [ "$checks" -gt 0 ] && printf '  OK    frames.pixelguard.checks=%s\n' "$checks" || { printf '  FAIL  frames.pixelguard.checks=%s\n' "${checks:-}"; rc=1; }
tally $rc "procfs"

echo
echo "PIXELGUARD: $pass green, $fail red"
[ "$fail" -eq 0 ]
