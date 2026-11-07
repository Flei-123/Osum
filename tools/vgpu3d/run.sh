#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh >/dev/null 2>&1
. tools/lib/summary.sh
summary_begin VGPU3D
T=$(mktemp -d)
XPID=""
cleanup() { [ -n "$XPID" ] && kill "$XPID" 2>/dev/null; rm -rf "$T"; }
trap 'cleanup; summary_guard' EXIT
K=${VGPU3D_KERNEL:-$T/k.mb}
if [ -z "${VGPU3D_KERNEL:-}" ]; then
    bash tools/build-kernel.sh "$K" >"$T/build.log" 2>&1 || { echo "build failed"; tail -20 "$T/build.log"; exit 1; }
fi
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

Xvfb -displayfd 3 -screen 0 800x600x24 -nolisten tcp 3>"$T/xdisplay" >/dev/null 2>&1 &
XPID=$!
i=0
while [ ! -s "$T/xdisplay" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
XD=":$(head -n1 "$T/xdisplay")"
[ "$XD" = ":" ] && { bad "Xvfb did not start"; summary_emit "$pass" "$fail" 1; exit 1; }

run_case() {
    local tag=$1 words=$2 device=$3 display=$4 stop=$5
    local out=$T/$tag.txt
    DISPLAY=$XD timeout 120 $QEMU_X86 -kernel "$K" -m 256 \
        -append "gfx disp nocursor fbtest fbhold $words nokbd nosched noproc nofs" \
        -serial "file:$out" -display "$display" -no-reboot \
        -vga std -device "$device" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$T/$tag.qemu" 2>&1 &
    local pid=$!
    local n=0
    while [ $n -lt 700 ]; do
        grep -aqE "$stop" "$out" 2>/dev/null && break
        kill -0 $pid 2>/dev/null || break
        sleep 0.2; n=$((n+1))
    done
    sleep 1
    kill $pid 2>/dev/null; wait $pid 2>/dev/null
}
field() { grep -a "^vgpu3d: $2" "$T/$1.txt" | head -n1 | sed -n "s/.*$3=\([0-9]*\).*/\1/p"; }
has() { grep -aq "^vgpu3d: $2" "$T/$1.txt"; }

echo "== virgl: capset, context, clear, readback, fences (virtio-gpu-gl-pci, host GL)"
run_case gl "vgpu3d" "virtio-gpu-gl-pci" "gtk,gl=on" "^vgpu3d: (end|no virgl|ctx failed|res failed|caps failed)"
has gl "virgl" && ok "device offers VIRTIO_GPU_F_VIRGL and the driver negotiated it" || bad "no virgl line"
has gl "capset id=1 ver=[0-9]* size=[1-9]" && ok "GET_CAPSET_INFO answers the virgl capset" || bad "no virgl capset info"
has gl "bgra render=1" && ok "virgl caps list B8G8R8A8 as renderable" || bad "bgra not renderable in caps"
RW=$(field gl "red wrong" "px"); RF=$(field gl "red fence" "fence")
BW=$(field gl "blue wrong" "px"); BF=$(field gl "blue fence" "fence")
FC=$(field gl "flush cycles" "cycles")
echo "   red wrong=${RW:-?} fence=${RF:-?}  blue wrong=${BW:-?} fence=${BF:-?}  fenced flush cycles=${FC:-?}"
[ "${RW:-x}" = "0" ] && ok "virgl CLEAR red: 4096 of 4096 pixels read back exact (0xFFFF0000)" || bad "red clear readback wrong (${RW:-none})"
[ "${BW:-x}" = "0" ] && ok "second CLEAR blue replaced every pixel (0xFF0000FF)" || bad "blue clear readback wrong (${BW:-none})"
[ "${RF:-0}" = "1" ] && [ "${BF:-0}" = "1" ] && ok "fenced SUBMIT_3D: response echoes fence flag and id" || bad "fence not echoed"
[ "${FC:-0}" -gt 0 ] && ok "fenced RESOURCE_FLUSH completed and echoed its fence" || bad "fenced flush failed"

echo "== control vgpu3dskip: second clear is not submitted -> the blue check must fail"
run_case skip "vgpu3d vgpu3dskip" "virtio-gpu-gl-pci" "gtk,gl=on" "^vgpu3d: end"
SB=$(field skip "blue wrong" "px"); SR=$(field skip "red wrong" "px")
echo "   red wrong=${SR:-?} blue wrong=${SB:-?}"
[ "${SB:-0}" = "4096" ] && [ "${SR:-x}" = "0" ] && ok "control: blue readback is 4096 pixels wrong while red stays exact (the blue check would FAIL)" || bad "control: skip not detected (${SB:-none})"

echo "== control 2D-only device: no virgl offered"
run_case flat "vgpu3d" "virtio-gpu-pci" "none" "^vgpu3d: (end|no virgl)"
has flat "no virgl" && ok "control: virtio-gpu-pci without GL offers no virgl, driver says so" || bad "control: 2D device not reported"
has flat "red wrong" && bad "control: 3D lines on a 2D device" || ok "control: no 3D submit on a 2D device"

echo "== control default: no word, no 3D traffic"
run_case off "" "virtio-gpu-gl-pci" "gtk,gl=on" "^vgpu: "
sleep 2
if ! grep -aq "^vgpu: bdf" "$T/off.txt"; then bad "control: virtio-gpu did not come up, the check proves nothing"
elif has off ""; then bad "control: vgpu3d lines without the word"
else ok "control: word absent -> no vgpu3d output"; fi

summary_emit "$pass" "$fail" 11
