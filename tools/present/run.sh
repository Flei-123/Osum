#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/present/run.sh -- W-PRESENT: how long is the picture exposed to the scan-out while a window is dragged quickly?
#
#   /root/jarvis/bin/heavy bash tools/present/run.sh        (CASES="1920x1080-new 1920x1080-old 3440x1440-new 3440x1440-old")
#
# WHY NOT PHOTOGRAPHS: QEMU's screendump reads the whole frame in one go while nobody writes, so a half-copied frame cannot be seen in it
# (docs/VSYNC.md section 2, measured: a picture series found NO torn picture with the frame boundary switched off). The shipping configuration
# (the Dell: stripe mode, no page flip, no vblank) copies every composed frame from the back buffer to the card; the scan-out tears that frame for as
# long as the copy lasts. So the thing to measure is the copy: how many octets one frame pushes and how long the window server is inside it.
# `wm: flush n= us= max= okt= rect=` (F12) gives n copies, microseconds summed, the longest, octets and rectangles since the last F12 dump.
#
# Cases: <res>-<new|old>; `old` boots with the word `fullrows` (whole screen rows, as before the fix) and is the COUNTER-PROOF: the same burst must
# push clearly more octets per frame there, or the measurement saw nothing. A tear needs the copy to outlast a refresh; octets per frame are
# hardware independent, microseconds are the VM's RAM speed (the card of the Dell is write-combining over PCIe: slower, see the report).
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
declare -A OKT US
for c in ${CASES:-1920x1080-new 1920x1080-old 3440x1440-new 3440x1440-old}; do
    res=${c%-*}; mode=${c#*-}
    extra=""; [ "$mode" = old ] && extra="extra=fullrows"
    echo "== case $c =="
    bash tools/design/eh6.sh "$TMPD/$c" res=$res accel=kvm $extra drehbuch="$(pwd)/tools/present/drag.txt" > "$TMPD/$c.log" 2>&1
    grep -a "FEHLGESCHLAGEN\|NO GEOMETRY\|schleppschnell" "$TMPD/$c.log" | head -5
    # the burst is the block between the LAST two F12 dumps
    ser="$TMPD/$c/serial.txt"
    mapfile -t FL < <(grep -a '^wm: flush n=' "$ser")
    mapfile -t BI < <(grep -a '^wm: bild n=' "$ser")
    nf=${#FL[@]}
    if [ "$nf" -lt 2 ]; then bad "case $c: fewer than two F12 dumps ($nf)"; continue; fi
    # the burst is the dump with the most copies among the last three (the very last dump is the one at the end of the run, after the burst)
    bi=$((nf-1)); bn=-1
    for k in $((nf-1)) $((nf-2)) $((nf-3)); do
        [ "$k" -ge 1 ] || continue
        kn=$(sed -E 's/.* n=([0-9]+).*/\1/' <<<"${FL[$k]}")
        [ "$kn" -gt "$bn" ] && { bn=$kn; bi=$k; }
    done
    last=${FL[$bi]}
    n=$(sed -E 's/.* n=([0-9]+).*/\1/' <<<"$last"); us=$(sed -E 's/.* us=([0-9]+).*/\1/' <<<"$last"); mx=$(sed -E 's/.* max=([0-9]+).*/\1/' <<<"$last")
    okt=$(sed -E 's/.* okt=([0-9]+).*/\1/' <<<"$last")
    bl=${BI[$bi]:-}
    echo "        copies=$n us_sum=$us us_max=$mx octets=$okt  per copy: $((n>0 ? okt/n : 0)) octets, $((n>0 ? us/n : 0)) us"
    echo "        ${bl}"
    OKT[$c]=$((n>0 ? okt/n : 0)); US[$c]=$((n>0 ? us/n : 0))
    [ "$n" -ge 20 ] && ok "case $c: $n frames copied during the burst" || bad "case $c: only $n copies in the burst"
    if [ -n "${KEEP:-}" ]; then mkdir -p "$KEEP"; cp "$ser" "$KEEP/$c.serial"; fi
    if [ -n "${KEEP:-}" ]; then cp "$TMPD/$c.log" "$KEEP/$c.log"; fi
    rm -rf "$TMPD/$c"
done
for r in 1920x1080 3440x1440; do
    nw=${OKT[$r-new]:-0}; od=${OKT[$r-old]:-0}
    [ "$nw" -gt 0 ] && [ "$od" -gt 0 ] || continue
    # the fix must push clearly fewer octets per frame than the whole-row copy (counter-proof turns red when it does not)
    [ $((nw*3/2)) -lt "$od" ] && ok "$r: octets per frame new $nw < old $od (fix pushes at most two thirds)" || bad "$r: new $nw vs old $od octets per frame -- no clear gain"
done
echo "PRESENT: $pass passed, $fail failed"
[ "$fail" = 0 ]
