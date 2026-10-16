#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vmsvga/panic.sh -- the KERNEL PANIC SCREEN reaches the VMSVGA host (r967, 16.10.2026).
#
# WHY: the only caller of vmsvga.present() was the desktop loop (gfx.bild_fertig). trap.fi paints the red panic screen (kgui.panikbild
#      ends with fb.flush) and stops: VRAM is right, but in VirtualBox (TRACES=0: the host does not watch VRAM) nobody ever sent the
#      UPDATE, so the Laptop kept showing the last desktop picture. Fix: trap.fi -> gfx.panik_present -> vmsvga.panic_present (after
#      the other cores are stopped: locks opened, one whole-picture UPDATE).
# WHAT (QEMU `-vga vmware -vnc`; words `krach krachjetzt` force a kernel exception, `absturzhalt` keeps the screen up):
#   1. the kernel reports the exception, the driver says "vmsvga: panic picture sent ok=1"
#   2. the screendump (VRAM direct) is the red panic screen (panic-red pixels > 30 %)
#   3. a VNC client that applies ONLY the UPDATE rectangles equals the screendump pixel for pixel (diff 0)
#   Control (optional): PANIC_CONTROL_KERNEL=<kernel.mb without the fix> -> its panic screen is in VRAM too, but it prints NO
#   "panic picture sent" line. NOTE: in QEMU `-kernel` boots the VNC picture of that old kernel is ALSO right (QEMU's VGA dirty bits
#   catch the VRAM writes after the BIOS text mode, see the timeline in <tag>.timeline): check 3 is not discriminating here. What
#   discriminates is the serial line (check 2); real hosts that ignore VRAM writes (VirtualBox, TRACES=0) need exactly that UPDATE.
#
# Usage: [VMSVGA_KERNEL=<kernel.mb>] [PANIC_CONTROL_KERNEL=<older kernel.mb>] bash tools/vmsvga/panic.sh
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

# run_case <tag> <kernel>
run_case() {
    local tag=$1 kern=$2
    cp -f "$T/d.img" "$T/$tag.img"
    local S="$T/$tag.sock" V="$T/$tag.vnc"
    timeout 150 $QEMU_X86 -S -kernel "$kern" -m 256 \
        -append "gfx nokbd nosched noproc noring3 logall absturzhalt krach krachjetzt" \
        -serial "file:$T/$tag.txt" -display none -no-reboot \
        -vga vmware -vnc "unix:$V" \
        -monitor "unix:$S,server,nowait" \
        -drive "file=$T/$tag.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$T/$tag.qemu" 2>&1 &
    local pid=$!
    python3 -I "$HERE/panic.py" "$S" "$V" "$T/$tag" "$T/$tag.txt" || true
    kill $pid 2>/dev/null
    wait $pid 2>/dev/null
}

echo "== panic screen with the fix"
run_case fix "$K"
chk "forced kernel exception reported" '[ "$(cat "$T/fix.diff" 2>/dev/null)" != "-3" ] && grep -aq "\*\*\* EXCEPTION" "$T/fix.txt"'
chk "driver sent the panic picture (serial line, ok=1)" 'grep -aq "^vmsvga: panic picture sent ok=1" "$T/fix.txt"'
chk "screendump is the red panic screen (> 30 % panic-red pixels)" \
    'r=$(cat "$T/fix.red" 2>/dev/null); p=$(cat "$T/fix.px" 2>/dev/null); [ "${p:-0}" -gt 0 ] && [ $((${r:-0} * 100 / p)) -gt 30 ]'
chk "VNC picture (UPDATE rects only) == screendump (0 differing pixels)" '[ "$(cat "$T/fix.diff" 2>/dev/null)" = "0" ]'

if [ -n "${PANIC_CONTROL_KERNEL:-}" ]; then
    echo "== control: kernel without the fix"
    run_case old "$PANIC_CONTROL_KERNEL"
    chk "control: the panic screen is in VRAM (> 30 % panic-red)" \
        'r=$(cat "$T/old.red" 2>/dev/null); p=$(cat "$T/old.px" 2>/dev/null); [ "${p:-0}" -gt 0 ] && [ $((${r:-0} * 100 / p)) -gt 30 ]'
    chk "control: no panic UPDATE sent (no serial line)" '! grep -aq "^vmsvga: panic picture sent" "$T/old.txt"'
fi

echo "vmsvga panic gate: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
