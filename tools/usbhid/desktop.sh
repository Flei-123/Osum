#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/marke-env.sh"
# SPDX-License-Identifier: GPL-2.0-only
# tools/usbhid/desktop.sh -- OHCI tablet on the REAL desktop (stick image, QEMU pci-ohci + usb-tablet). The QEMU cases of run.sh use the
# ehcitest window, which has its own loop; VirtualBox's default tablet sat on the OHCI and the desktop (window server loop) never polled
# it (`ohci: pulse polls=0`). Case 1: tablet moves reach the desktop -> serial `ohci: pulse ... wmpolls>0 reports>0 errors=0`.
# COUNTER-PROOF (case 2): kernel word `nousb` (no USB driver started) -> no `ohci: pulse` line and no tablet report reach the desktop,
# so the numbers of case 1 really come from the OHCI poll of the window server loop. (A run of the gate on a kernel without
# kgui's poll_wm call -- main before this round -- shows wmpolls=0 / reports=0: the VirtualBox symptom.)
# Usage: [STICK_DIR=<dir with orientos-usb.img>] [IMG=<file>] [SETTLE=8] bash tools/usbhid/desktop.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
HERE=$(pwd)/tools/usbhid
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
SETTLE=${SETTLE:-8}
if [ -n "${IMG:-}" ]; then
    IMAGE=$IMG
elif [ -n "${STICK_DIR:-}" ] && [ -f "$STICK_DIR/${MARKE_DATEI}-usb.img" ]; then
    IMAGE=$STICK_DIR/"${MARKE_DATEI}-usb".img
else
    mkdir -p "$T/build"
    PARTTAB=mbr bash tools/usbimg/build.sh "$T/build" >"$T/build.log" 2>&1 || { echo "stick build failed"; tail -15 "$T/build.log"; exit 1; }
    IMAGE=$T/build/"${MARKE_DATEI}-usb".img
fi
KVM=(-accel tcg)
[ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)

run_case() { # run_case <tag> <extra cmdline words>
    local tag=$1 words=$2 D=$T/$1
    mkdir -p "$D"
    cp -f "$IMAGE" "$D/stick.img"
    local off=$((2048 * 512))
    mcopy -o -i "$D/stick.img@@$off" ::/limine.conf "$D/l.conf" || return 1
    sed -i 's/^timeout: .*/timeout: 1/' "$D/l.conf"
    awk -v w="$words" 'BEGIN{d=0} /^ *cmdline:/ && d==0 { d=1; if (w == "nousb") { sub(/ usb /, " nousb ") } print; next } { print }' "$D/l.conf" >"$D/l2.conf"
    mcopy -o -i "$D/stick.img@@$off" "$D/l2.conf" ::/limine.conf
    timeout 420 qemu-system-x86_64 "${KVM[@]}" -m 2048 -smp 4 \
        -device qemu-xhci,id=xhci \
        -drive if=none,id=stick,format=raw,file="$D/stick.img" \
        -device usb-storage,bus=xhci.0,drive=stick,bootindex=1 \
        -device pci-ohci,id=oh -device usb-tablet,bus=oh.0 \
        -netdev user,id=n0 -device e1000e,netdev=n0 \
        -vga vmware -display none -no-reboot \
        -serial file:"$D/serial.txt" \
        -monitor unix:"$D/mon.sock",server,nowait \
        -qmp unix:"$D/qmp.sock",server,nowait >"$D/qemu.txt" 2>&1 &
    local pid=$!
    python3 -I "$HERE/desktop.py" "$D/mon.sock" "$D/qmp.sock" "$D/serial.txt" "$D/o" "$SETTLE" >"$D/py.txt" 2>&1 || true
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    [ -n "${KEEP:-}" ] && mkdir -p "$KEEP" && cp -f "$D/serial.txt" "$KEEP/$tag.serial.txt" 2>/dev/null
    return 0
}
run_case on ""
[ "$(cat "$T/on/o.login" 2>/dev/null)" = 1 ] && ok "logged in" || { bad "login"; tail -5 "$T/on/py.txt"; }
read -r n wm rp er < "$T/on/o.res" 2>/dev/null || { n=0; wm=0; rp=0; er=0; }
echo "  desktop: pulse lines=$n wmpolls=$wm reports=$rp errors=$er"
grep -aq '^ohci: base=.* devices=1' "$T/on/serial.txt" && ok "ohci enumerated the tablet" || bad "ohci enumeration"
[ "${n:-0}" -ge 1 ] && ok "pulse lines on the desktop ($n)" || bad "no 'ohci: pulse' line (tablet events never reached the desktop)"
[ "${wm:-0}" -ge 1 ] && ok "window server loop polls the OHCI (wmpolls=$wm)" || bad "wmpolls=0: the desktop loop never polls the OHCI"
[ "${rp:-0}" -ge 20 ] && ok "tablet reports arrive (reports=$rp)" || bad "tablet reports missing (reports=$rp, expected >=20)"
# one or two control errors during enumeration are normal (VirtualBox shows 2 too); what matters is that reports flow
[ "${er:-0}" -le 2 ] && ok "OHCI errors stay small (errors=$er)" || bad "ohci errors=$er (expected <=2)"
if [ -z "${NOCOUNTER:-}" ]; then
    run_case off "nousb"
    read -r n2 wm2 rp2 er2 < "$T/off/o.res" 2>/dev/null || { n2=0; wm2=0; rp2=0; er2=0; }
    echo "  counter-proof nousb: pulse lines=$n2 wmpolls=$wm2 reports=$rp2"
    [ "${n2:-0}" -eq 0 ] && [ "${rp2:-0}" -eq 0 ] && ok "counter-proof: no pulse line, no reports without the USB driver" || bad "counter-proof: pulse=$n2 reports=$rp2 with nousb"
fi
echo "usbhid desktop: $pass ok, $fail fail"
[ "$fail" = 0 ]
