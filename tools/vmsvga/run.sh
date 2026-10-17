#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vmsvga/run.sh -- VMware SVGA II driver (kernel/drv/gpu/vmsvga.fi) in QEMU (16.10.2026).
#
# WHAT IT MEASURES (QEMU only: `-vga vmware -vnc`, kernel word `vmsvgahw` = test bed in kgui.fi + verify mode)
#   1. DETECTION   serial line `vmsvga: bdf=.. id=0x90000002 ... hc=1`, mode set by "Weg 3" (no loader framebuffer).
#   2. MODES       the test bed switches 800x600 -> 1024x768 -> 1280x720 -> 640x480 -> 800x600 through vmode.follow_host (the same
#                  call the host-resize poll makes). Each screendump has the panel size and is BYTE-IDENTICAL to the Bochs-VBE
#                  reference run (`-vga std`, same kernel, same words, same picture).
#   3. UPDATE RECTS a tiny VNC client applies ONLY what QEMU's VNC server sends (it copies only the UPDATE rectangles); after every
#                  mode it must equal the screendump (which reads VRAM directly) -> the host was told about every changed pixel.
#   4. HW CURSOR   defs >= 1, moves >= 59, ZERO picture octets for pointer moves, and the VNC client receives a cursor shape
#                  (RichCursor) with both opaque and transparent pixels. The screendump has no pointer (pixel equality in 2).
#   5. OCTETS      60 frames with a 48x48 dirty rect: <= 64 KB per frame; 2 s idle: < 100 KB/s.
#   6. VERIFY      kernel-side check (`vmsvga: verify bad=0 frames=N`, N > 0): nothing changed outside the sent rectangle.
#   FULL WAY      default WITHOUT word `vmsvgarect` (since the VirtualBox failure of image 54db5a98): every frame = ONE whole-screen UPDATE,
#                 SYNC/BUSY handshake, no diff flush; the same pixel/VNC checks run again (case `fullw`), maxframe >= a whole frame.
#                 The cases above (main, ruhe) run with `vmsvgarect` = the rectangle path.
#   IDLE/HEAL    3 s idle after the trailing UPDATE: port I/O <= 16 (`pio=`), traces=0, heal stages ran (>= 12 for 4 mode changes).
#   Real desktop (stick image, Limine, 4 cores, random input, VNC rects only == screendump): tools/vmsvga/desktop.sh.
#   Controls (each MUST be detected):
#      novmsvga  -> no detection line, no panel lines (the driver is off, `-kernel` has no other framebuffer)
#      wmruhe    -> whole screen dirty every frame: the 64 KB per frame check must fail
#
#   HOST HINT     (X4) host_pending + follow_host with an injected VMMDev hint: odd sizes, oversize (shrunk), 5 hints.
#
# NOT PROVEN HERE: VirtualBox / VMware (FIFO, CURSOR_BYPASS_3, ALPHA cursor, VMMDev request layout) -- QEMU 7.2 has none of them. The VMMDev
# transport is proven on the laptop: VBoxManage controlvm OrientOS setvideomodehint W H 32 + jarvisctl screenshot (reports/20261017-X4-resize.md).
#
# Usage: [VMSVGA_KERNEL=<kernel.mb>] bash tools/vmsvga/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh >/dev/null 2>&1
HERE=$(pwd)/tools/vmsvga
if [ -n "${OUT:-}" ]; then mkdir -p "$OUT"; T=$OUT; else T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fi
K=${VMSVGA_KERNEL:-$T/k.mb}
if [ -z "${VMSVGA_KERNEL:-}" ]; then
    bash tools/build-kernel.sh "$K" >"$T/build.log" 2>&1 || { echo "build failed"; tail -20 "$T/build.log"; exit 1; }
fi
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

python3 tools/osum/mkfs.py build "$T/d.img" 4096 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf >/dev/null 2>&1

# run_case <tag> <-vga value> <words> <mode: full|short|frames>
run_case() {
    local tag=$1 vga=$2 words=$3 mode=$4
    cp -f "$T/d.img" "$T/$tag.img"
    local S="$T/$tag.sock" V="$T/$tag.vnc"
    timeout 170 $QEMU_X86 -kernel "$K" -m 256 \
        -append "gfx disp nocursor fbtest fbhold vmsvgahw $words nokbd nosched noproc nofs" \
        -serial "file:$T/$tag.txt" -display none -no-reboot \
        -vga "$vga" -vnc "unix:$V" \
        -monitor "unix:$S,server,nowait" \
        -drive "file=$T/$tag.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$T/$tag.qemu" 2>&1 &
    local pid=$!
    python3 -I "$HERE/harness.py" "$S" "$V" "$T/$tag" "$T/$tag.txt" "$mode" "$vga" || true
    kill $pid 2>/dev/null
    wait $pid 2>/dev/null
}

echo "== main: -vga vmware (driver on)"
run_case main vmware "vmsvgarect" full
echo "== reference: -vga std (Bochs VBE, same kernel, same picture)"
run_case ref std "vmsvgarect" full
echo "== full-update way (default, no vmsvgarect): same pictures, whole-screen UPDATEs"
run_case fullw vmware "" full
echo "== control: novmsvga"
run_case nov vmware "novmsvga" short
echo "== control: wmruhe"
run_case ruhe vmware "vmsvgarect wmruhe" frames

M=$T/main.txt
chk "detected: id=0x90000002, hardware cursor reported" 'grep -aqE "^vmsvga: bdf=0x[0-9a-f]+ id=0x90000002 .* hc=1" "$M"'
chk "Weg 3 mode 800x600 at boot" 'grep -aqE "^vmsvga: bdf=.* mode=800x600 " "$M"'
chk "five panel lines in order 800x600,1024x768,1280x720,640x480,800x600" \
    '[ "$(grep -a "^vmsvga: panel=" "$M" | sed "s/^vmsvga: panel=//" | tr "\n" " ")" = "800x600 1024x768 1280x720 640x480 800x600 " ]'
for i in 0 1 2 3 4; do
    want=$(grep -a "^vmsvga: panel=" "$M" | sed -n "$((i+1))p" | sed "s/^vmsvga: panel=//")
    got=$(cat "$T/main.p$i.size" 2>/dev/null)
    chk "screendump $i has the panel size ($want)" '[ -n "$want" ] && [ "$want" = "$got" ]'
done
for i in 1 2 3 4; do
    chk "mode $i pixel-identical to the Bochs reference" '[ -s "$T/main.p$i.ppm" ] && cmp -s "$T/main.p$i.ppm" "$T/ref.p$i.ppm"'
done
for i in 0 1 2 3 4; do
    chk "VNC picture (UPDATE rects only) == screendump, mode $i" '[ "$(cat "$T/main.p$i.vncdiff" 2>/dev/null)" = "0" ]'
done
chk "cursor: hw=1, moves >= 59, defs >= 1" \
    'l=$(grep -a "^vmsvga: move hw=" "$M" | tail -1); echo "$l" | grep -q "hw=1" && [ "$(echo "$l" | sed -n "s/.* moves=\([0-9]*\).*/\1/p")" -ge 59 ] && [ "$(echo "$l" | sed -n "s/.* defs=\([0-9]*\).*/\1/p")" -ge 1 ]'
chk "pointer moves carry 0 picture octets" '[ "$(grep -a "^vmsvga: move hw=" "$M" | tail -1 | sed -n "s/.* okt=\([0-9]*\).*/\1/p")" = "0" ]'
chk "VNC client received a cursor shape (opaque and transparent pixels)" \
    'read -r cw ch co ct < "$T/main.cursor" 2>/dev/null; [ "${cw:-0}" -gt 0 ] && [ "${co:-0}" -gt 0 ] && [ "${ct:-0}" -gt 0 ]'
chk "frames with a 48x48 rect: every frame <= 64 KB" \
    '[ "$(grep -a "^vmsvga: frames hw=" "$M" | tail -1 | sed -n "s/.* maxframe=\([0-9]*\).*/\1/p")" -le 65536 ]'
chk "idle 2 s: < 100 KB/s" '[ "$(grep -a "^vmsvga: idle okt=" "$M" | tail -1 | sed -n "s/.* okt=\([0-9]*\).*/\1/p")" -lt 200000 ]'
chk "idle 3 s (after the trailing UPDATE): port I/O <= 16 (host-hint poll only; QEMU has none)" \
    '[ "$(grep -a "^vmsvga: idle okt=" "$M" | tail -1 | sed -n "s/.* pio=\([0-9]*\).*/\1/p")" -le 16 ]'
chk "TRACES register written: traces=0 in the report line" 'grep -a "^vmsvga: bdf=" "$M" | tail -1 | grep -q " traces=0"'
chk "mode-change self-heal ran (4 modes x 3 stages: heal >= 12)" \
    '[ "$(grep -a "^vmsvga: bdf=" "$M" | tail -1 | sed -n "s/.* heal=\([0-9]*\).*/\1/p")" -ge 12 ]'
chk "verify: bad=0 over frames > 10" \
    'l=$(grep -a "^vmsvga: verify bad=" "$M" | tail -1); echo "$l" | grep -q "bad=0 " && [ "$(echo "$l" | sed -n "s/.* frames=\([0-9]*\).*/\1/p")" -gt 10 ]'
chk "4 resizes, 0 errors" 'l=$(grep -a "^vmsvga: bdf=" "$M" | tail -1); echo "$l" | grep -q " rsz=4 " && echo "$l" | grep -q " err=0"'
chk "safety net: one full UPDATE after 10 s without any" 'grep -a "^vmsvga: bdf=" "$M" | tail -1 | grep -qE " safe=[1-9]"'
chk "no FIFO overflow (full=0)" 'grep -a "^vmsvga: bdf=" "$M" | tail -1 | grep -q " full=0 "'

# HOST HINT (X4, 17.10.2026): the VirtualBox hint arrives through the guest device (VMMDev), not the VMSVGA registers. QEMU has no VMMDev, so
# the test bed injects the hint (vmsvga.vmm_fake) and the REAL poll code runs: first poll sees it once (p1=0), the second returns it, then
# vmode.follow_host switches. Odd width, odd height, a screen bigger than card/map window (shrunk, same aspect), back to a normal size.
hl() { grep -a "^vmsvga: hint in=$1 " "$M" | head -1; }
chk "hint stage: five hints ran" '[ "$(grep -ac "^vmsvga: hint in=" "$M")" = 5 ]'
chk "hint 1137x683 (odd width): two polls, mode follows, device agrees, verify bad=0" \
    'hl 1137x683 | grep -q "p1=0 pend=1137x683 rc=0 mode=1137x683 dev=1137x683 bad=0$"'
chk "hint 1280x721 (odd height): mode follows" 'hl 1280x721 | grep -q "p1=0 pend=1280x721 rc=0 mode=1280x721 dev=1280x721 bad=0$"'
chk "hint 4096x2304 (too big): accepted, shrunk to fit, same aspect, device agrees" \
    'l=$(hl 4096x2304); echo "$l" | grep -q "p1=0 pend=4096x2304 rc=0 " && m=$(echo "$l" | sed -n "s/.* mode=\([0-9]*\)x\([0-9]*\) dev=\([0-9]*\)x\([0-9]*\) .*/\1 \2 \3 \4/p") && set -- $m && [ "$1" -lt 4096 ] && [ "$1" -ge 640 ] && [ "$1" = "$3" ] && [ "$2" = "$4" ] && d=$(( $1*2304 - $2*4096 )) && [ "${d#-}" -le $(( $2*4096/50 )) ]'
chk "hint 1920x1080 and 1024x768: mode follows (no stale state after the shrink)" \
    'hl 1920x1080 | grep -q "pend=1920x1080 rc=0 mode=1920x1080 dev=1920x1080 bad=0$" && hl 1024x768 | grep -q "pend=1024x768 rc=0 mode=1024x768 dev=1024x768 bad=0$"'

# full-update way (default): QEMU cannot show the VirtualBox failure, but the pictures must stay right and the cost must be a full frame
F=$T/fullw.txt
chk "full way: detected, mode 800x600 at boot" 'grep -aqE "^vmsvga: bdf=.* mode=800x600 " "$F"'
for i in 1 2 3 4; do
    chk "full way: mode $i pixel-identical to the Bochs reference" '[ -s "$T/fullw.p$i.ppm" ] && cmp -s "$T/fullw.p$i.ppm" "$T/ref.p$i.ppm"'
done
for i in 0 1 2 3 4; do
    chk "full way: VNC picture (UPDATE rects only) == screendump, mode $i" '[ "$(cat "$T/fullw.p$i.vncdiff" 2>/dev/null)" = "0" ]'
done
chk "full way: every frame is a whole-screen UPDATE (maxframe >= 800x600x4)" \
    '[ "$(grep -a "^vmsvga: frames hw=" "$F" | tail -1 | sed -n "s/.* maxframe=\([0-9]*\).*/\1/p")" -ge 1920000 ]'
chk "full way: idle 3 s: port I/O <= 16 and no picture data" \
    'l=$(grep -a "^vmsvga: idle okt=" "$F" | tail -1); [ "$(echo "$l" | sed -n "s/.* pio=\([0-9]*\).*/\1/p")" -le 16 ] && [ "$(echo "$l" | sed -n "s/.* okt=\([0-9]*\).*/\1/p")" -lt 200000 ]'
chk "full way: mode-change self-heal ran (heal >= 12)" \
    '[ "$(grep -a "^vmsvga: bdf=" "$F" | tail -1 | sed -n "s/.* heal=\([0-9]*\).*/\1/p")" -ge 12 ]'
chk "full way: no FIFO overflow (full=0), no resize error" 'l=$(grep -a "^vmsvga: bdf=" "$F" | tail -1); echo "$l" | grep -q " full=0 " && echo "$l" | grep -q " err=0"'

# controls: the same measurements must FAIL
chk "control novmsvga: no detection line" '! grep -aq "^vmsvga: bdf=" "$T/nov.txt"'
chk "control novmsvga: no picture (panel stays 0x0)" '! grep -aqE "^vmsvga: panel=[1-9]" "$T/nov.txt"'
chk "control wmruhe: whole screen dirty -> > 64 KB per frame" \
    '[ "$(grep -a "^vmsvga: frames hw=" "$T/ruhe.txt" | tail -1 | sed -n "s/.* maxframe=\([0-9]*\).*/\1/p")" -gt 65536 ]'

echo "vmsvga gate: $pass ok, $fail fail"
[ "$fail" = 0 ]
