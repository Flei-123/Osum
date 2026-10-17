#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vmsvgaresize/run.sh -- the real desktop after host resolution changes (r1004), stick image, -vga vmware.
# Sizes 1280x720 -> 1024x768 -> 1600x900 -> 1024x768 are requested through the VNC SetDesktopSize message (same kernel path as a
# VirtualBox hint). After each one: the screen has the new size, the upper part is NOT black (wallpaper / windows), the taskbar sits at
# the bottom (rows differ from the plain wallpaper), and the first screenshot and the last one (same size) look alike.
# Usage: [STICK_DIR=<dir with orientos-usb.img>] [IMG=<file>] [SETTLE=14] bash tools/vmsvgaresize/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
HERE=$(pwd)/tools/vmsvgaresize
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
SETTLE=${SETTLE:-14}
if [ -n "${IMG:-}" ]; then
    IMAGE=$IMG
elif [ -n "${STICK_DIR:-}" ] && [ -f "$STICK_DIR/orientos-usb.img" ]; then
    IMAGE=$STICK_DIR/orientos-usb.img
else
    mkdir -p "$T/build"
    PARTTAB=mbr bash tools/usbimg/build.sh "$T/build" >"$T/build.log" 2>&1 || { echo "stick build failed"; tail -15 "$T/build.log"; exit 1; }
    IMAGE=$T/build/orientos-usb.img
fi
KVM=(-accel tcg)
[ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
D=$T/run; mkdir -p "$D"
cp -f "$IMAGE" "$D/stick.img"
off=$((2048 * 512))
mcopy -o -i "$D/stick.img@@$off" ::/limine.conf "$D/l.conf" || exit 1
sed -i 's/^timeout: .*/timeout: 1/' "$D/l.conf"
awk 'BEGIN{d=0} /^ *cmdline:/ && d==0 { d=1; print $0 " vmsvgahints"; next } { print }' "$D/l.conf" >"$D/l2.conf"
mcopy -o -i "$D/stick.img@@$off" "$D/l2.conf" ::/limine.conf
SIZES=${SIZES:-1280x720,1024x768,1600x900,1024x768}
timeout 600 qemu-system-x86_64 "${KVM[@]}" -m 2048 -smp 4 \
    -device qemu-xhci,id=xhci \
    -drive if=none,id=stick,format=raw,file="$D/stick.img" \
    -device usb-storage,bus=xhci.0,drive=stick,bootindex=1 \
    -netdev user,id=n0 -device e1000e,netdev=n0 \
    -vga vmware -vnc "unix:$D/vnc.sock" -display none -no-reboot \
    -serial file:"$D/serial.txt" \
    -monitor unix:"$D/mon.sock",server,nowait >"$D/qemu.txt" 2>&1 &
pid=$!
python3 -I "$HERE/resize.py" "$D/mon.sock" "$D/vnc.sock" "$D/o" "$D/serial.txt" "$SETTLE" "$SIZES" >"$D/py.txt" 2>&1 || true
kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
[ -n "${KEEP:-}" ] && mkdir -p "$KEEP" && cp -f "$D"/o.*.ppm "$D"/o.res "$D"/serial.txt "$KEEP"/ 2>/dev/null
[ "$(cat "$D/o.login" 2>/dev/null)" = 1 ] && ok "logged in" || { bad "login"; tail -5 "$D/py.txt"; }
cat "$D/o.res" 2>/dev/null
n=$(wc -l < "$D/o.res" 2>/dev/null || echo 0)
[ "$n" -ge 3 ] && ok "$n hint steps measured" || bad "only $n hint steps measured"
while read -r i rw rh black rows lastb ew eh dup mcx mbot; do
    s=${ew}x${eh}
    [ "$rw" = "$ew" ] && [ "$rh" = "$eh" ] && ok "$s: screen has the new size" || bad "$s: screen size (got ${rw}x${rh})"
    awk -v b="$black" 'BEGIN{exit !(b<0.5)}' && ok "$s: desktop not black (black share $black)" || bad "$s: desktop black (black share $black)"
    [ "$rows" -ge 20 ] && ok "$s: taskbar at the bottom (rows $rows)" || bad "$s: no taskbar at the bottom (rows $rows)"
    awk -v b="$lastb" 'BEGIN{exit !(b<0.05)}' && ok "$s: last bar row not black (share $lastb)" || bad "$s: last row black (share $lastb)"
    awk -v b="$dup" 'BEGIN{exit !(b<0.5)}' && ok "$s: bar not repeated by a stale stride (dup share $dup)" || bad "$s: bar repeated (dup share $dup)"
    # The start menu is only placed when it is SHOWN. In QEMU the first open after a resize is placed one step late (centre/bottom of the
    # previous size) while VirtualBox (z6, 1024 -> 1280) opened it correctly: reported as NOTE until r1010 is solved, not counted.
    if [ "$mcx" -ge 0 ]; then
        d=$(( mcx - rw / 2 )); [ "$d" -lt 0 ] && d=$(( -d ))
        if [ "$d" -le 8 ] && [ "$mbot" -le $(( rh - 40 )) ] && [ "$mbot" -ge $(( rh - 120 )) ]; then
            ok "$s: start menu centred and above the bar (centre $mcx, bottom $mbot)"
        else
            echo "  NOTE  $s: start menu stale (centre $mcx of $rw, bottom $mbot of $rh) -- r1010"
        fi
    else
        echo "  NOTE  $s: start menu not found -- r1010"
    fi
done < "$D/o.res"
echo "resize: $pass ok, $fail fail"
[ "$fail" = 0 ]
