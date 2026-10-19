#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/edidroom/run.sh -- W-EDID: an EDID / host size the card or the kernel window cannot take must never end in a black screen.
#
# WHAT IT MEASURES (QEMU, Bochs VGA with EDID `-device VGA,edid=on,xres=..,yres=..,vgamem_mb=..`, words `gfx disp fbtest fbhold`)
#   1. EDID 1366x768 (width not divisible by 8; the card reads back 1360): before the fix "fb: kein Rahmenpuffer" (black screen). Now:
#      `fb: retry 1360x768`, fb 1360x768, screendump the same size and not black.
#   2. EDID 1920x1080 / 2560x1440 on a card with 4 MiB VRAM: the boot ladder (vmode.boot_step, 15/16 steps, aspect kept) ends in a mode that
#      FITS the VRAM, is >= 640x480, same aspect, screendump == fb size, not black.
#   3. EDID 2048x1152 on 16 MiB (the QEMU EDID maximum): no retry at all (the ladder only runs when something is refused).
#   4. Nothing can fit (1 MiB VRAM): ends in ONE clean "kein Rahmenpuffer" line, the kernel lives on (`fb: hold`), the ladder is bounded.
#   5. In-kernel promises `fb: room N / 12` (fb.selftest5): run_room / tile_room on synthetic tile masks -- a device tile splitting the window
#      (tile_room says 13, no run of 13 exists), the framebuffer's own tiles count as free, a full window has no room, n=0 / n>16 are false.
#   6. COUNTER-PROOFS (must be RED, otherwise the checks above prove nothing): word `nobootretry` (no ladder) -> 1366x768 and 4 MiB end in
#      "kein Rahmenpuffer"; word `roomold` (run_room only counts tiles, the pre-W-L2 rule) -> `room` < 12.
#   The run-time half (host hint over the window limit -> shrunk mode, no rollback) is tools/vmsvgaresize/big.sh (gate vmsvgabig).
#
# Usage: [EDIDROOM_KERNEL=<kernel.mb>] bash tools/edidroom/run.sh   (builds its own kernel when unset)
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh >/dev/null 2>&1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
K=${EDIDROOM_KERNEL:-$T/k.mb}
if [ -z "${EDIDROOM_KERNEL:-}" ]; then
    bash tools/build-kernel.sh "$K" >"$T/build.log" 2>&1 || { echo "build failed"; tail -20 "$T/build.log"; exit 1; }
fi
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# run_case <tag> <xres> <yres> <vgamem_mb> [extra kernel words]  (blocking; call with & to run in parallel)
run_case() {
    local tag=$1 x=$2 y=$3 vm=$4 words=${5:-}
    timeout 90 $QEMU_X86 -kernel "$K" -m 512 \
        -append "gfx disp nocursor fbtest fbhold nokbd nosched noproc nofs $words" \
        -serial "file:$T/$tag.txt" -display none -no-reboot \
        -device "VGA,edid=on,xres=$x,yres=$y,vgamem_mb=$vm" \
        -monitor "unix:$T/$tag.sock,server,nowait" >/dev/null 2>&1 &
    local pid=$!
    local i=0
    while [ $i -lt 400 ]; do
        grep -qaE "^fb: hold" "$T/$tag.txt" 2>/dev/null && break
        kill -0 $pid 2>/dev/null || break
        sleep 0.15; i=$((i+1))
    done
    python3 -I - "$T/$tag.sock" "$T/$tag.ppm" <<'PYEOF'
import os, socket, sys, time
sock, f = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX)
try:
    s.connect(sock)
except OSError:
    sys.exit(0)
s.settimeout(3.0)
time.sleep(0.4)
try: s.recv(65536)
except OSError: pass
s.sendall(("screendump %s\n" % f).encode())
last = -1
end = time.time() + 6
while time.time() < end:
    try: g = os.path.getsize(f)
    except OSError: g = -1
    if g > 0 and g == last: break
    last = g; time.sleep(0.25)
try: s.recv(65536)
except OSError: pass
s.close()
PYEOF
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
    return 0
}

# fbgeo <tag> -> "WxH" of the framebuffer line, empty when none
fbgeo() { grep -aoE '^fb: [0-9]+x[0-9]+x32' "$T/$1.txt" | head -1 | sed -E 's/^fb: ([0-9]+x[0-9]+)x32/\1/'; }
retries() { grep -ac '^fb: retry ' "$T/$1.txt"; }
nonefb() { grep -ac '^fb: kein Rahmenpuffer' "$T/$1.txt"; }
room() { grep -aoE '^fb: room [0-9]+ / [0-9]+' "$T/$1.txt" | head -1 | sed -E 's/^fb: room //'; }
# dumpinfo <tag> -> "WxH permille_nonblack"
dumpinfo() { python3 -I - "$T/$1.ppm" <<'PYEOF'
import sys
try:
    d = open(sys.argv[1], 'rb').read()
    parts = d.split(b'\n', 3)
    w, h = map(int, parts[1].split())
    body = parts[3]
except Exception:
    print("0x0 0"); sys.exit()
n = sum(1 for i in range(0, len(body), 3) if body[i] or body[i+1] or body[i+2])
print("%dx%d %d" % (w, h, (1000 * n) // max(1, w * h)))
PYEOF
}

run_case a 1366 768 16 &
run_case b 1920 1080 4 &
run_case c 2560 1440 4 &
run_case d 2048 1152 16 &
wait
run_case e 1920 1080 1 &
run_case f 1366 768 16 nobootretry &
run_case g 1920 1080 4 nobootretry &
run_case h 1366 768 16 roomold &
wait

echo "== 1. EDID 1366x768 (card takes widths divisible by 8)"
grep -a '^fb: nat=' "$T/a.txt" | head -1 | sed 's/^/   /'
[ "$(fbgeo a)" = "1360x768" ] && ok "fb is 1360x768 (width rounded down to 8, not 'no framebuffer')" || bad "fb = '$(fbgeo a)'"
grep -aq '^fb: retry 1360x768$' "$T/a.txt" && ok "one retry line: 1360x768" || bad "retry line missing"
read -r DS DP <<<"$(dumpinfo a)"
[ "$DS" = "1360x768" ] && ok "screendump is 1360x768" || bad "screendump size $DS"
[ "$DP" -ge 1 ] && ok "screen is not black ($DP per mille lit)" || bad "screen is black"

echo "== 2. EDID 1920x1080 and 2560x1440 on a 4 MiB card"
for t in b:1920:1080 c:2560:1440; do
    tag=${t%%:*}; r=${t#*:}; ex=${r%%:*}; ey=${r##*:}
    G=$(fbgeo $tag); W=${G%x*}; H=${G#*x}
    echo "   $tag: wanted ${ex}x${ey} -> '${G}' after $(retries $tag) retries"
    if [ -n "$G" ]; then
        ok "$tag: a framebuffer exists ($G)"
        [ "$W" -ge 640 ] && [ "$H" -ge 480 ] && ok "$tag: not below 640x480" || bad "$tag: too small $G"
        [ $((W * H * 4)) -le 4194304 ] && ok "$tag: fits 4 MiB of VRAM ($((W * H * 4)) bytes)" || bad "$tag: does not fit VRAM"
        # same aspect within 2 %: |W*ey - H*ex| * 50 <= W*ey
        D=$((W * ey - H * ex)); [ $D -lt 0 ] && D=$((-D))
        [ $((D * 50)) -le $((W * ey)) ] && ok "$tag: aspect kept" || bad "$tag: aspect lost ($G)"
        read -r DS DP <<<"$(dumpinfo $tag)"
        [ "$DS" = "$G" ] && ok "$tag: screendump == fb size" || bad "$tag: dump $DS != fb $G"
        [ "$DP" -ge 1 ] && ok "$tag: screen not black ($DP per mille)" || bad "$tag: screen is black"
    else
        bad "$tag: no framebuffer (black screen)"
    fi
done

echo "== 3. EDID 2048x1152 on 16 MiB (nothing refused)"
[ "$(fbgeo d)" = "2048x1152" ] && ok "fb is 2048x1152" || bad "fb = '$(fbgeo d)'"
[ "$(retries d)" = "0" ] && ok "no retry" || bad "retried $(retries d) times"

echo "== 4. nothing fits (1 MiB card, EDID 1920x1080)"
[ "$(nonefb e)" = "1" ] && ok "exactly one 'kein Rahmenpuffer' line" || bad "none lines: $(nonefb e)"
[ "$(retries e)" -ge 1 ] && [ "$(retries e)" -le 40 ] && ok "ladder ran and is bounded ($(retries e) retries)" || bad "retries = $(retries e)"
grep -aq '^fb: hold' "$T/e.txt" && ok "kernel lives on after the failed init" || bad "kernel stopped after the failed init"

echo "== 5. window room rules (fb.selftest5, synthetic masks)"
R=$(room a); echo "   room $R"
[ "$R" = "12 / 12" ] && ok "fb: room 12 / 12" || bad "fb: room '$R'"

echo "== 6. counter-proofs (broken variants must be RED)"
[ -z "$(fbgeo f)" ] && [ "$(nonefb f)" = "1" ] && ok "nobootretry: 1366x768 ends in 'kein Rahmenpuffer' (old bug reproduced)" || bad "nobootretry did not reproduce the bug ('$(fbgeo f)')"
[ -z "$(fbgeo g)" ] && [ "$(nonefb g)" = "1" ] && ok "nobootretry: 1920x1080 on 4 MiB ends in 'kein Rahmenpuffer'" || bad "nobootretry (4 MiB) did not reproduce the bug ('$(fbgeo g)')"
RO=$(room h); echo "   roomold: room $RO"
[ -n "$RO" ] && [ "$RO" != "12 / 12" ] && ok "roomold: promises fail ($RO)" || bad "roomold stayed green ('$RO')"

echo "edidroom: $pass OK / $fail FAIL"
[ "$fail" -eq 0 ]
