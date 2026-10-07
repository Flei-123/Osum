#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/region/run.sh -- THE DAMAGE REGION (docs/COMPOSITOR.md stage S2) IS A SAVING, NEVER A CHANGE.
#
#   bash tools/region/run.sh        (start it through /root/jarvis/bin/heavy)
#
# `wm.damage` keeps one bounding box AND a list of disjoint rectangles (lib/fui/region.fi). When the list covers clearly less than
# the box, `compose_one` paints the rectangles one by one. The promise tested here: the picture is the same, pixel for pixel, as
# with the old single box (the kernel word `norgn`), and the saving is real (`wm: phase ... rgn= saved=` of the F12 dump).
#
# One drehbuch, two runs: the pointer jumps between far corners (every move is two small disjoint rectangles), the start menu is
# opened with the Super key (a blurred window, the blur grows its rectangle) and closed again; a picture after every step.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
export DESIGNBUILD="$TMPD/build"

cat > "$TMPD/dreh.txt" <<'DREH'
warteauf 'launcher: ready' || 90
warte 3
fahre 100,100
fahre 1100,700
warte 1
foto a1-jump
fahre 200,600
fahre 1000,150
warte 1
foto a2-jump
taste meta_l
warte 2
fahre 60,300
fahre 1100,60
warte 1
foto a3-menu-far
fahreauf lzeile1
warte 1
foto a4-menu-hover
fahre 1100,400
fahreauf lzeile3
warte 1
foto a5-menu-hover2
taste esc
warte 2
fahre 640,400
fahre 100,700
warte 1
foto a6-closed
taste f12
warte 2
DREH

run() { # run <name> <extra capture args...>
    local name=$1; shift
    bash tools/design/capture.sh "$TMPD/$name" uitrace=yes accel=kvm startstyle=list drehbuch="$TMPD/dreh.txt" "$@" \
        > "$TMPD/$name.log" 2>&1
    grep -a "FEHLGESCHLAGEN" "$TMPD/$name.log" | head -3
}

echo "== 1. the same drehbuch with the region and without it (norgn) =="
run reg extra=phases
run box "extra=norgn phases"
for n in a1-jump a2-jump a3-menu-far a4-menu-hover a5-menu-hover2 a6-closed; do
    [ -s "$TMPD/reg/$n.ppm" ] && [ -s "$TMPD/box/$n.ppm" ] && ok "both runs took picture $n" \
        || bad "picture $n is missing in one run"
done

echo "== 2. the pictures are the same, pixel for pixel =="
python3 - "$TMPD/reg" "$TMPD/box" <<'PY' && ok "no differing pixel outside the clock and the two counters" || bad "the region changed the picture"
import sys
from PIL import Image
a, b = sys.argv[1], sys.argv[2]
bad = 0
for n in ("a1-jump", "a2-jump", "a3-menu-far", "a4-menu-hover", "a5-menu-hover2", "a6-closed"):
    ia = Image.open("%s/%s.ppm" % (a, n)).convert("RGB")
    ib = Image.open("%s/%s.ppm" % (b, n)).convert("RGB")
    if ia.size != ib.size:
        print("  size differs in", n); bad += 1; continue
    w, h = ia.size
    pa, pb = ia.load(), ib.load()
    diff = []
    for y in range(h):
        for x in range(w):
            # masked: the toasts with RAM / CPU at the top right, the clock at the right end of the task bar
            if (x >= w - 220 and y < 110) or (x >= w - 160 and y >= h - 50):
                continue
            if pa[x, y] != pb[x, y]:
                diff.append((x, y))
    print("  %-16s %d differing pixels" % (n, len(diff)), ("first " + str(diff[:3])) if diff else "")
    if diff:
        bad += 1
sys.exit(1 if bad else 0)
PY

echo "== 3. the saving is real, and the counter-run has none =="
L1=$(grep -a '^wm: phase n=' "$TMPD/reg/serial.txt" | tail -1)
L2=$(grep -a '^wm: phase n=' "$TMPD/box/serial.txt" | tail -1)
echo "        with the region:    ${L1#wm: phase }"
echo "        with norgn:         ${L2#wm: phase }"
R1=$(printf '%s' "$L1" | grep -oE ' rgn=[0-9]+' | tr -dc 0-9)
S1=$(printf '%s' "$L1" | grep -oE ' saved=[0-9]+' | tr -dc 0-9)
R2=$(printf '%s' "$L2" | grep -oE ' rgn=[0-9]+' | tr -dc 0-9)
[ "${R1:-0}" -gt 0 ] && ok "frames composed rectangle by rectangle: $R1" || bad "no frame used the region (rgn=${R1:-?})"
[ "${S1:-0}" -gt 100000 ] && ok "pixels not painted because of it: $S1" || bad "the region saved nothing (saved=${S1:-?})"
[ -n "$L2" ] && [ "${R2:-1}" = 0 ] && ok "with norgn no frame used the region" || bad "norgn still used the region (rgn=${R2:-?})"

echo
echo "REGION: $pass passed, $fail failed"
[ "$fail" = 0 ]
