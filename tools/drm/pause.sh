#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
firnenv_need_firnc1
ROOT=$(pwd)
D=$(mktemp -d)
trap '[ -n "${DRM_OUT:-}" ] && mkdir -p "$DRM_OUT" && cp "$D"/*.ser "$DRM_OUT"/ 2>/dev/null; rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$*"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$*"; }
fin() { echo "DRM-PAUSE-GATE: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }
QEMU=${QEMU_X86:-qemu-system-x86_64}
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
LDREAL=$(readlink -f /lib/ld-musl-x86_64.so.1 2>/dev/null || echo /usr/lib/x86_64-linux-musl/libc.so)
SCREEN="python3 -I compat/linuxkpi/hosttest/screen.py"
mkdir -p "$D/bin"
musl-gcc -static -O2 -o "$D/bin/t_drm" tools/drm/t_drm.c 2> "$D/cc.txt" && ok "test program builds" || { bad "test program"; head -5 "$D/cc.txt"; fin; }
. tools/unterbau/image.sh
EXTRA_SPEC="/lib/sans.ttf=assets/osum-sans.ttf /lib/mono.ttf=assets/osum-mono.ttf" build_image "$ROOT" "$D/img" && ok "image builds" || { bad "image"; fin; }
[ -n "${KERNEL_OLD:-}" ] && [ -n "${KERNEL:-}" ] || { bad "KERNEL and KERNEL_OLD are required"; fin; }

runvm() {
    local name=$1 kernel=$2 i=0 pid
    cp -f "$D/img/disk.img" "$D/$name.img"
    timeout 150 $QEMU "${KVM[@]}" -smp 1 -kernel "$kernel" -m 512 \
        -append "osum vfs gfx wm wig desk wmshell wmdauer nobootterm nopuls script=/bin/t_drm alt;exit" -serial "file:$D/$name.ser" \
        -display none -no-reboot -drive "file=$D/$name.img,format=raw,if=ide,index=0" \
        -monitor "unix:$D/$name.sock,server,nowait" -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
    pid=$!
    while [ $i -lt 480 ]; do
        grep -qa "DRM_HOLD" "$D/$name.ser" 2>/dev/null && break
        kill -0 $pid 2>/dev/null || break
        sleep 0.25; i=$((i+1))
    done
    $SCREEN dump "$D/$name.sock" "$D/$name.before.ppm"
    python3 -I tools/drm/pointer.py "$D/$name.sock" 4
    $SCREEN dump "$D/$name.sock" "$D/$name.after.ppm"
    kill $pid 2>/dev/null
    wait $pid 2>/dev/null
    rm -f "$D/$name.img"
}

judge_new() {
    local q
    q=$(python3 -I tools/drm/quadrants.py "$D/new.before.ppm" alt 2>&1)
    case "$q" in "quadrants ok"*) ok "new: picture intact while the desktop runs ($q)" ;; *) bad "new: picture damaged ($q)" ;; esac
    q=$(python3 -I tools/drm/quadrants.py "$D/new.after.ppm" alt 2>&1)
    case "$q" in "quadrants ok"*) ok "new: picture intact after pointer moves ($q)" ;; *) bad "new: picture damaged by pointer moves ($q)" ;; esac
    cmp -s "$D/new.before.ppm" "$D/new.after.ppm" && ok "new: screen identical before and after pointer moves" || bad "new: screen changed under the master"
}

judge_old() {
    local qb qa
    qb=$(python3 -I tools/drm/quadrants.py "$D/old.before.ppm" alt 2>&1)
    qa=$(python3 -I tools/drm/quadrants.py "$D/old.after.ppm" alt 2>&1)
    case "$qb$qa" in *"quadrants wrong"*) ok "old kernel counter-proof: desktop damages the master's picture ($qb / $qa)" ;; *) bad "old kernel counter-proof: picture survived without the pause" ;; esac
}

runvm new "$KERNEL"
runvm old "$KERNEL_OLD"
grep -qa "DRM_HOLD" "$D/new.ser" && ok "new: test reached the hold" || bad "new: test did not reach the hold"
grep -qa "EXCEPTION" "$D/new.ser" && bad "new: kernel exception" || ok "new: no kernel exception"
judge_new
judge_old
fin
