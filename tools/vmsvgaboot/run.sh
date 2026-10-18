#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vmsvgaboot/run.sh -- W-C3: the screen is fitted to the host at BOOT and the UI scale follows the final size.
# QEMU never sends a host hint, so the kernel word `vmsvgaboot` plays 2400x1400 through kgui.host_boot_fit (the same call a VirtualBox
# VMMDev hint takes at boot). Checks (QEMU vmware card with 64 MiB video memory, stick image):
#   1. serial `vmsvga: bootfit 1024x768 hint 2400x1400` then `vmsvga: bootfit -> WxH rc=0 scale=2` (screen switched BEFORE the desktop; the
#      QEMU card refuses widths above 2368, so the fit is shrunk to ~2250x1312 -- the scale still follows the REQUESTED size: 2)
#   2. the screendump after login has that size, is not black, and the taskbar is at the bottom
#   3. taskbar height at scale 2 is about twice the height at scale 1 (control run without the word: scale 1)
# Usage: [STICK_DIR=<dir with orientos-usb.img>] [IMG=<file>] bash tools/vmsvgaboot/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
HERE=$(pwd)/tools/vmsvgaboot
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
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
off=$((2048 * 512))
run_one() { # <tag> <extra words>
    local tag=$1 words=$2 D=$T/$1
    mkdir -p "$D"
    cp -f "$IMAGE" "$D/stick.img"
    mcopy -o -i "$D/stick.img@@$off" ::/limine.conf "$D/l.conf" || return 1
    sed -i 's/^timeout: .*/timeout: 1/' "$D/l.conf"
    awk -v ex="$words" 'BEGIN{d=0} /^ *cmdline:/ && d==0 { d=1; print $0 " " ex; next } { print }' "$D/l.conf" >"$D/l2.conf"
    mcopy -o -i "$D/stick.img@@$off" "$D/l2.conf" ::/limine.conf
    timeout 600 qemu-system-x86_64 "${KVM[@]}" -m 2048 -smp 4 \
        -device qemu-xhci,id=xhci \
        -drive if=none,id=stick,format=raw,file="$D/stick.img" \
        -device usb-storage,bus=xhci.0,drive=stick,bootindex=1 \
        -netdev user,id=n0 -device e1000e,netdev=n0 \
        -vga none -device vmware-svga,vgamem_mb=64 -vnc "unix:$D/vnc.sock" -display none -no-reboot \
        -serial file:"$D/serial.txt" \
        -monitor unix:"$D/mon.sock",server,nowait >"$D/qemu.txt" 2>&1 &
    local pid=$!
    python3 -I "$HERE/boot.py" "$D/mon.sock" "$D/vnc.sock" "$D/o" "$D/serial.txt" >"$D/py.txt" 2>&1 || true
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    [ -n "${KEEP:-}" ] && mkdir -p "$KEEP/$1" && cp -f "$D"/o.*.ppm "$D/serial.txt" "$D/py.txt" "$D/o.res" "$KEEP/$1"/ 2>/dev/null
    return 0
}
run_one fit "vmsvgaboot"
run_one ctl ""
D=$T/fit
[ "$(cat "$D/o.login" 2>/dev/null)" = 1 ] && ok "fit: logged in" || { bad "fit: login"; tail -5 "$D/py.txt"; }
line=$(grep -a '^vmsvga: bootfit  *-> ' "$D/serial.txt" | head -1)
echo "  NOTE  $line"
sw=$(echo "$line" | sed -n 's/^vmsvga: bootfit  *-> \([0-9]*\)x\([0-9]*\) rc=0 scale=2.*/\1/p'); sh=$(echo "$line" | sed -n 's/^vmsvga: bootfit  *-> \([0-9]*\)x\([0-9]*\) rc=0 scale=2.*/\2/p')
[ -n "$sw" ] && [ "$sw" -ge 2000 ] && ok "fit: boot fit ${sw}x${sh}, rc 0, UI scale 2" || bad "fit: boot fit line wrong: '$line'"
read -r fw fh fblack frows < "$D/o.res" 2>/dev/null || { fw=0; fh=0; fblack=1; frows=0; }
[ "$fw" = "${sw:-0}" ] && [ "$fh" = "${sh:-0}" ] && ok "fit: screen dump is ${fw}x${fh} (as logged)" || bad "fit: screen dump ${fw}x${fh} (logged ${sw:-0}x${sh:-0})"
awk -v b="$fblack" 'BEGIN{exit !(b<0.5)}' && ok "fit: desktop not black (share $fblack)" || bad "fit: desktop black (share $fblack)"
[ "$frows" -ge 20 ] && ok "fit: taskbar at the bottom (rows $frows)" || bad "fit: no taskbar (rows $frows)"
D=$T/ctl
[ "$(cat "$D/o.login" 2>/dev/null)" = 1 ] && ok "ctl: logged in" || bad "ctl: login"
grep -aq '^vmsvga: bootfit' "$D/serial.txt" && bad "ctl: boot fit line without the word" || ok "ctl: no boot fit without the word (QEMU has no hint)"
read -r cw ch cblack crows < "$D/o.res" 2>/dev/null || { cw=0; ch=0; }
[ "$cw" = 1024 ] || [ "$cw" -ge 640 ] && ok "ctl: screen stays at its boot mode (${cw}x${ch})" || bad "ctl: screen ${cw}x${ch}"
# bar height from the taskbar geometry line the program logs (`taskbar: geom edge=.. x=.. y=.. w=.. h=..`): the pixel scan in boot.py
# (.bar) hits its 199-row limit whenever the wallpaper row used as reference happens to differ (control run: 199 of 199)
bar_h() { grep -a '^taskbar: geom ' "$1/serial.txt" | tail -1 | sed -n 's/.* h=\([0-9][0-9]*\).*/\1/p'; }
fh_bar=$(bar_h "$T/fit"); ch_bar=$(bar_h "$T/ctl"); fh_bar=${fh_bar:-0}; ch_bar=${ch_bar:-0}
echo "  NOTE  taskbar height: fit $fh_bar px, control $ch_bar px"
[ "$ch_bar" -gt 0 ] && [ "$fh_bar" -ge $(( ch_bar * 17 / 10 )) ] && ok "taskbar is ~2x higher at scale 2 ($fh_bar vs $ch_bar px)" || bad "taskbar height does not follow the scale ($fh_bar vs $ch_bar px)"
echo "vmsvgaboot: $pass ok, $fail fail"
[ "$fail" = 0 ]
