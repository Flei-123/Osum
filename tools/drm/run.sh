#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
firnenv_need_firnc1
ROOT=$(pwd)
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$*"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$*"; }
fin() { [ -n "${DRM_OUT:-}" ] && mkdir -p "$DRM_OUT" && cp "$D"/*.ser "$D"/*.ppm "$DRM_OUT"/ 2>/dev/null; echo "DRM-GATE: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }
QEMU=${QEMU_X86:-qemu-system-x86_64}
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
LDREAL=$(readlink -f /lib/ld-musl-x86_64.so.1 2>/dev/null || echo /usr/lib/x86_64-linux-musl/libc.so)
SCREEN="python3 -I compat/linuxkpi/hosttest/screen.py"

if [ -n "${KERNEL:-}" ]; then cp "$KERNEL" "$D/k.mb"; ok "kernel supplied"; else
    bash tools/build-kernel.sh "$D/k.mb" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; fin; }
fi
mkdir -p "$D/bin"
musl-gcc -static -O2 -o "$D/bin/t_drm" tools/drm/t_drm.c 2> "$D/cc.txt" && ok "test program builds" || { bad "test program"; head -5 "$D/cc.txt"; fin; }
. tools/unterbau/image.sh
build_image "$ROOT" "$D/img" && ok "image builds" || { bad "image"; fin; }

runvm() {
    local name=$1 arg=$2 i=0 pid
    cp -f "$D/img/disk.img" "$D/$name.img"
    timeout 120 $QEMU "${KVM[@]}" -smp 1 -kernel "$D/k.mb" -m 512 \
        -append "osum vfs gfx ${DRM_KARGS:-} nokbd nosched noproc nofs script=/bin/t_drm $arg;exit" -serial "file:$D/$name.ser" \
        -display none -no-reboot -drive "file=$D/$name.img,format=raw,if=ide,index=0" \
        -monitor "unix:$D/$name.sock,server,nowait" -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
    pid=$!
    while [ $i -lt 400 ]; do
        grep -qa "DRM_HOLD" "$D/$name.ser" 2>/dev/null && break
        kill -0 $pid 2>/dev/null || break
        sleep 0.25; i=$((i+1))
    done
    $SCREEN dump "$D/$name.sock" "$D/$name.ppm"
    wait $pid
    rm -f "$D/$name.img"
}

runvm shown ""
runvm noset noset

for t in stat_card0 stat_render readdir_dri open_card0 version cap_dumb getresources getconnector create_dumb map_dumb mmap \
    mmap_bad_offset_refused addfb2 fstat_rdev getresources_fbs setcrtc getcrtc fstat_rdev_render render_setcrtc_refused closed_fd_reaps_handles; do
    line=$(grep -a "^T t_drm\.$t " "$D/shown.ser" | tail -1)
    case "$line" in *" PASS"*) ok "$t" ;; *) bad "$t: ${line:-no line}" ;; esac
done
grep -qa "DRM_DONE" "$D/shown.ser" && ok "test ran to the end" || bad "test did not finish"
grep -qa "EXCEPTION" "$D/shown.ser" && bad "kernel exception" || ok "no kernel exception"
q=$(python3 -I tools/drm/quadrants.py "$D/shown.ppm" 2>&1)
case "$q" in "quadrants ok"*) ok "screendump shows the four colour quadrants ($q)" ;; *) bad "screendump: $q" ;; esac
line=$(grep -a "^T t_drm\.getcrtc " "$D/noset.ser" | tail -1)
case "$line" in *" PASS"*) ok "counter-proof noset: crtc has no fb" ;; *) bad "counter-proof noset getcrtc: ${line:-no line}" ;; esac
q=$(python3 -I tools/drm/quadrants.py "$D/noset.ppm" 2>&1)
case "$q" in "quadrants ok"*) bad "counter-proof noset: picture shown without SETCRTC" ;; *) ok "counter-proof noset: no picture without SETCRTC ($q)" ;; esac
fin
