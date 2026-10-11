#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/drag/run.sh -- W-DRAG: the title bar must stay in EVERY frame while a window is dragged (and during the swing after the release).
#
#   /root/jarvis/bin/heavy bash tools/drag/run.sh            all four cases (about 4 x 3 min)
#   CASES="2-new 2-old" bash tools/drag/run.sh               only some of them
#
# Cases: <scale>-<new|old>; scale 1 = 1280x800, scale 2 = 3440x1440 (Justin's Dell). `old` boots the kernel with the word `nodragbar`
# (the lifted window is painted without frame and title bar, as before the fix) and is the COUNTER-PROOF: the same series must show
# frames without a bar there, or the check measured nothing.
# What is measured: tools/design/drive.py `schleppfoto` grabs the title bar of the terminal window, drags it in 6 steps (button held,
# a screenshot after every step), lets go and takes screenshots at once and 1.5 s later; tools/drag/check.py asks per picture whether the
# title bar colour (median of a strip next to the pointer, taken BEFORE the grab) still stands left of the pointer.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
for c in ${CASES:-2-new 2-old 1-new 1-old}; do
    sc=${c%-*}; mode=${c#*-}
    if [ "$sc" = 2 ]; then res=3440x1440; else res=1280x800; fi
    extra=""; [ "$mode" = old ] && extra="extra=nodragbar"
    echo "== case $c ($res, $mode) =="
    bash tools/design/eh6.sh "$TMPD/$c" res=$res accel=kvm $extra drehbuch="$(pwd)/tools/drag/drag$sc.txt" > "$TMPD/$c.log" 2>&1
    grep -a "^schleppfoto: geom\|FEHLGESCHLAGEN" "$TMPD/$c.log" | head -3
    python3 tools/drag/check.py "$TMPD/$c" d "$TMPD/$c.log" > "$TMPD/$c.chk" 2>&1; rc=$?
    sed 's/^/        /' "$TMPD/$c.chk"
    if [ "$mode" = new ]; then
        [ $rc = 0 ] && ok "case $c: the title bar is in every frame of the drag and the swing" || bad "case $c: the title bar is missing in some frame (rc=$rc)"
    else
        [ $rc = 1 ] && ok "case $c (counter-proof nodragbar): frames without a bar are seen" || bad "case $c: the counter-proof did not turn red (rc=$rc) -- the check is blind"
    fi
    if [ -n "${KEEP:-}" ]; then mkdir -p "$KEEP/$c"; cp "$TMPD/$c"/d-*.ppm "$KEEP/$c/" 2>/dev/null; cp "$TMPD/$c.chk" "$KEEP/$c.chk"; fi
    rm -rf "$TMPD/$c"
done
echo "DRAG: $pass passed, $fail failed"
[ "$fail" = 0 ]
