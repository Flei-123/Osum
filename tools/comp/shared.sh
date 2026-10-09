#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/comp/shared.sh -- docs/COMPOSITOR.md stage S3: SHARED WINDOW BUFFERS AND THE WINDOW TABLE PAGE.
#
#   bash tools/comp/shared.sh        (start it through /root/jarvis/bin/heavy)
#
# Three things are tested, each with a counter-proof:
#
#   1. /bin/shmtest (kernel/user/shmtest.fi) in the running desktop: a window made with a memfd (MFD_FRAMES), the window table page
#      (read-only, consistent, our window in it), the buffer through WM_BUFFD, no leak over 20 windows -- and the SCREENSHOT shows the
#      gradient the client painted into the shared buffer (the compositor composes from the client's frames).
#      Counter-proof: with the kernel word `noshare` the window gets a buffer of its own, WM_DAMAGE is refused, and the same
#      screenshot does NOT show the gradient.
#   2. The desktop scene (start menu, file manager) with shared buffers and with `noshare` gives the same pictures, pixel for pixel
#      (outside the clock and the toasts): sharing is a saving and never a change.
#   3. The copies: `wm: shared n= blitpx= ...` of the F12 dump. With shared buffers the scene windows copy no pixel through WIG_BLIT.
set -uo pipefail
cd "$(dirname "$0")/../.."
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
pass=0; fail=0
# One fixed image time for every build of this gate: the file dates the explorer shows must not depend on the wall clock
# (a minute change between two runs made digits differ -- the old flake).
export CAPTURE_TIME=${CAPTURE_TIME:-1760000000}
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

val() { # val <serial> <name> <field 3|4>   the last line "shmtest: name a b"
    grep -a "^shmtest: $2 " "$1" | tail -1 | awk -v f="$3" '{print $f}'
}

echo "== 1. shmtest in the desktop: shared window, table page, WM_BUFFD, no leak =="
run_shm() { # run_shm <name> <extra words>
    bash tools/alltag/build.sh "$D/$1" kbd=no accel=kvm shot=yes uitrace=no \
        "extra=wigapp=/bin/shmtest wighalt=40 $2" progs="shmtest sh echo" > "$D/$1.log" 2>&1
}
run_shm sh1 ""
S="$D/sh1/serial.txt"
grep -a '^shmtest:' "$S" | sed 's/^/        /'
[ "$(val "$S" window 3)" = 1 ] && ok "the buffer: memfd (MFD_FRAMES) made, truncated and mapped" || bad "no shared buffer in the program"
[ "$(val "$S" shared 3)" = 1 ] && ok "WM_INFO / WI_SHARED says 1 for the window" || bad "the window is not shared"
DM=$(val "$S" damage 3); DE=$(val "$S" damage 4)
[ -n "$DM" ] && [ "$DM" = "$DE" ] && ok "WM_DAMAGE named the whole window without a copy: $DM pixels" || bad "WM_DAMAGE: '$DM' of '$DE'"
[ "$(val "$S" t-magic 3)" = 1111577687 ] && [ "$(val "$S" t-magic 4)" = 1 ] && ok "the window table page: magic WTAB, version 1" || bad "table magic: $(val "$S" t-magic 3) / $(val "$S" t-magic 4)"
[ "$(val "$S" t-seq 3)" = 0 ] && ok "the table is consistent (even sequence number $(val "$S" t-seq 4))" || bad "the table sequence number is odd"
R=$(val "$S" t-rows 3)
[ "${R:-0}" -ge 2 ] && ok "the table lists $R windows (desktop, task bar and ours at least)" || bad "table rows: '$R'"
[ "$(val "$S" t-row 3)" = 320 ] && [ "$(val "$S" t-row 4)" = 200 ] && ok "our window is in the table with size 320 x 200" || bad "our row: $(val "$S" t-row 3) x $(val "$S" t-row 4)"
TSH=$(val "$S" t-shm 3)
[ "${TSH:-0}" -gt 0 ] && ok "the row names the shared object ($TSH) and an owner ($(val "$S" t-shm 4))" || bad "the row has no shared object"
[ "$(val "$S" t-write-no 3)" = 1 ] && ok "COUNTER-PROOF: a writable mapping of the table page is refused" || bad "the table page could be mapped writable"
[ "$(val "$S" buffd 3)" = 1 ] && ok "WM_BUFFD gave root a descriptor of the window's buffer" || bad "WM_BUFFD refused"
[ "$(val "$S" b-match 3)" = "$(val "$S" b-match 4)" ] && [ -n "$(val "$S" b-match 3)" ] && ok "through WM_BUFFD the pixels are the ones painted: $(val "$S" b-match 3) of $(val "$S" b-match 4)" || bad "WM_BUFFD pixels differ: $(val "$S" b-match 3) of $(val "$S" b-match 4)"
[ "$(val "$S" b-write-no 3)" = 1 ] && ok "COUNTER-PROOF: the buffer cannot be mapped writable through WM_BUFFD" || bad "WM_BUFFD mapping was writable"
L=$(val "$S" leak 3)
[ -n "$L" ] && [ "$L" -lt 63 ] && ok "no leak over 20 windows of 63 frames: $L frames missing (a leak would be about 1260)" || bad "leak: '$L' frames"
[ "$(val "$S" done 3)" = 1 ] && ok "shmtest ran to the end" || bad "shmtest did not finish"

# the screenshot: the gradient is on the screen where the client area begins
cat > "$D/grad.py" <<'PY'
import sys
from PIL import Image
img = Image.open(sys.argv[1]).convert("RGB")
ox, oy = int(sys.argv[2]), int(sys.argv[3])
px = img.load()
good = tot = 0
for y in range(4, 196, 12):
    for x in range(4, 316, 12):
        X, Y = ox + x, oy + y
        if X >= img.size[0] or Y >= img.size[1]:
            continue
        tot += 1
        if px[X, Y] == (x & 255, y & 255, 0x80):
            good += 1
print(good, tot)
PY
OX=$(val "$S" at 3); OY=$(val "$S" at 4)
if [ -s "$D/sh1/desktop.ppm" ] && [ -n "$OX" ]; then
    read G T < <(python3 "$D/grad.py" "$D/sh1/desktop.ppm" "$OX" "$OY")
    [ "${T:-0}" -gt 100 ] && [ "$G" -ge $((T * 9 / 10)) ] && ok "the screenshot shows the client's gradient: $G of $T sample points are exact" || bad "the screenshot shows the gradient at only $G of $T points"
else
    bad "no screenshot or no window position (at '$OX' '$OY')"
fi

echo "== 1b. counter-proof: with the kernel word noshare the window is not shared and the screen shows none of the gradient =="
run_shm sh2 noshare
S2="$D/sh2/serial.txt"
[ "$(val "$S2" shared 3)" = 0 ] && ok "noshare: WI_SHARED says 0" || bad "noshare: the window is shared anyway"
DM2=$(val "$S2" damage 3)
[ -n "$DM2" ] && [ "$DM2" != "$DE" ] && ok "noshare: WM_DAMAGE is refused" || bad "noshare: WM_DAMAGE worked ('$DM2')"
OX2=$(val "$S2" at 3); OY2=$(val "$S2" at 4)
if [ -s "$D/sh2/desktop.ppm" ] && [ -n "$OX2" ]; then
    read G2 T2 < <(python3 "$D/grad.py" "$D/sh2/desktop.ppm" "$OX2" "$OY2")
    [ "${T2:-0}" -gt 100 ] && [ "$G2" -lt $((T2 / 10)) ] && ok "noshare: the screenshot does NOT show the gradient ($G2 of $T2 points)" || bad "noshare: the screenshot shows the gradient at $G2 of $T2 points"
else
    bad "noshare: no screenshot"
fi

# the pointer leaves the task bar button before the last picture: its tooltip appears after a delay that depends on the host load (a flaky 4000 pixel diff)
echo "== 2. the desktop scene with shared buffers and with noshare: the same pictures =="
cat > "$D/dreh.txt" <<'DREH'
warteauf 'launcher: ready' || 90
warte 30
taste f12
warte 4
foto c1-idle
taste f12
klick 24,780
warte 4
foto c2-menu
taste f12
taste esc
warte 2
klick 24,780
warte 3
klickauf start_File Explorer
warte 14
fahre 1250,780
warte 8
foto c3-explorer
taste f12
warte 3
taste f12
DREH
run() { # run <name> <extra capture args...>
    local name=$1; shift
    bash tools/design/capture.sh "$D/$name" uitrace=yes accel=kvm drehbuch="$D/dreh.txt" "$@" > "$D/$name.log" 2>&1
    grep -a "FEHLGESCHLAGEN" "$D/$name.log" | head -3
}
run shr "extra=phases"
run nsh "extra=noshare phases"
run shr2 "extra=phases"
for n in c1-idle c2-menu c3-explorer; do
    [ -s "$D/shr/$n.ppm" ] && [ -s "$D/nsh/$n.ppm" ] && ok "both runs took picture $n" || bad "picture $n is missing in one run"
done
python3 tools/comp/shared_cmp.py "$D/shr" "$D/nsh" "$D/shr2" && ok "no differing pixel outside the clock, the toasts and the terminal text" || bad "sharing changed the picture"

echo "== 3. the copies: pixels the kernel copied out of a client (WIG_BLIT) per frame =="
sumf() { # sumf <serial> <field>   sum of a field of all `wm: shared` lines
    grep -a '^wm: shared n=' "$1" | grep -oE " $2=[0-9]+" | tr -dc '0-9\n' | awk '{s+=$1} END{print s+0}'
}
sumn() { grep -a '^wm: shared n=' "$1" | sed -E 's/^wm: shared n=([0-9]+).*/\1/' | awk '{s+=$1} END{print s+0}'; }
F1=$(sumn "$D/shr/serial.txt"); F2=$(sumn "$D/nsh/serial.txt")
B1=$(sumf "$D/shr/serial.txt" blitpx); B2=$(sumf "$D/nsh/serial.txt" blitpx)
P1=$(sumf "$D/shr/serial.txt" shpx); P2=$(sumf "$D/nsh/serial.txt" shpx)
echo "        shared:  frames=$F1 blitpx=$B1 shpx=$P1 attach(last)=$(grep -a '^wm: shared' "$D/shr/serial.txt" | tail -1 | grep -oE 'attach=[0-9]+')"
echo "        noshare: frames=$F2 blitpx=$B2 shpx=$P2"
grep -a '^wm: shared' "$D/shr/serial.txt" | sed 's/^/        shr  /' | tail -8
grep -a '^wm: shared' "$D/nsh/serial.txt" | sed 's/^/        nsh  /' | tail -8
phase() { grep -a '^wm: phase n=' "$1" | awk '{ for (i = 1; i <= NF; i++) { split($i, kv, "="); if (kv[1] == "n") n += kv[2]; if (kv[1] == "win") w += kv[2]; if (kv[1] == "px") p += kv[2] } } END { printf "%d %d %d\n", n, w, p }'; }
read PN1 PW1 PP1 < <(phase "$D/shr/serial.txt"); read PN2 PW2 PP2 < <(phase "$D/nsh/serial.txt")
[ "${PN1:-0}" -gt 0 ] && [ "${PN2:-0}" -gt 0 ] && echo "        window phase per frame: shared $((PW1 / PN1)) us, noshare $((PW2 / PN2)) us (frames $PN1 / $PN2); kernel copies per frame: shared $((B1 / F1)) px, noshare $((B2 / F2)) px"
[ "${B2:-0}" -gt 0 ] && ok "noshare copies pixels out of the clients: $B2 in $F2 frames" || bad "noshare copied nothing (blitpx=$B2)"
[ "${P1:-0}" -gt 0 ] && ok "shared windows named $P1 pixels of damage without a copy" || bad "no shared damage (shpx=$P1)"
[ "${B1:-0}" -lt $((B2 / 4)) ] && ok "copies fell from $B2 to $B1 pixels (a fourth or less)" || bad "copies fell only from $B2 to $B1 pixels"

echo
echo "SHARED: $pass passed, $fail failed"
[ "$fail" = 0 ]
