#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/usbhid/run.sh -- r1003: USB HID (mouse wheel + right button, tablet, keyboard) per host controller.
# Cases (QEMU, word `ehcitest` opens a 9 s measuring window, host injects through QMP, guest prints `hidwin:`):
#   OHCI (pci-ohci)  x mouse / tablet / kbd   -> GATED (new driver kernel/drv/usb/ohci.fi, VirtualBox default controller)
#   xHCI (qemu-xhci) x mouse / tablet / kbd   -> GATED (existing driver, regression)
#   EHCI (usb-ehci)  x mouse / tablet         -> NOTE only (ehci.fi has a keyboard only; gap listed in the report)
# COUNTER-PROOF: the same OHCI mouse case with the word `nousb` (driver not started) must show nothing.
# Usage: [HW_KERNEL=<kernel.mb>] bash tools/usbhid/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh >/dev/null 2>&1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
K=${HW_KERNEL:-$T/k.mb}
if [ -z "${HW_KERNEL:-}" ]; then
    bash tools/build-kernel.sh "$K" >"$T/build.log" 2>&1 || { echo "build failed"; tail -20 "$T/build.log"; exit 1; }
fi
python3 tools/osum/mkfs.py build "$T/d.img" 32768 --v3 /lib/ >/dev/null 2>&1
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '  NOTE  %s\n' "$1"; }
fld() { grep -a '^hidwin: keys' "$T/$1.txt" | tail -1 | sed -n "s/.* $2=\([0-9]*\).*/\1/p"; }

launch() { # launch <tag> <words> <qemu device args...>
    local tag=$1 words=$2; shift 2
    cp -f "$T/d.img" "$T/$tag.img"
    timeout 90 $QEMU_X86 -kernel "$K" -m 512 -append "$words ehcitest" -serial "file:$T/$tag.txt" \
        -display none -no-reboot -vga std -drive "file=$T/$tag.img,format=raw,if=ide,index=0" \
        -qmp "unix:$T/$tag.sock,server=on,wait=off" "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
}
drive() { python3 tools/usbhid/drive.py "$T/$1.sock" "$T/$1.txt" "$2" >/dev/null 2>&1 & }

# three guests at a time (no shared state: own disk copy, own socket)
launch om  "usb hidgen" -device pci-ohci,id=c -device usb-mouse,bus=c.0
launch ot  "usb hidgen" -device pci-ohci,id=c -device usb-tablet,bus=c.0
launch ok  "usb hidgen" -device pci-ohci,id=c -device usb-kbd,bus=c.0
launch on  "nousb hidgen"   -device pci-ohci,id=c -device usb-mouse,bus=c.0
sleep 2; drive om mouse; drive ot tablet; drive ok kbd; drive on mouse; wait
launch xm  "usb hidgen" -device qemu-xhci,id=c -device usb-mouse,bus=c.0
launch xt  "usb hidgen" -device qemu-xhci,id=c -device usb-tablet,bus=c.0
launch xk  "usb hidgen" -device qemu-xhci,id=c -device usb-kbd,bus=c.0
launch em  "usb hidgen ehci" -device usb-ehci,id=c -device usb-mouse,bus=c.0
sleep 2; drive xm mouse; drive xt tablet; drive xk kbd; drive em mouse; wait

chk() { # chk <label> <tag> <field> <min> [gated|note]
    local v; v=$(fld "$2" "$3"); v=${v:-0}
    if [ "$v" -ge "$4" ]; then ok "$1 ($3=$v)"; elif [ "${5:-gated}" = note ]; then note "$1 ($3=$v, expected >=$4)"; else bad "$1 ($3=$v, expected >=$4)"; fi
}
echo "== OHCI"
chk "ohci mouse: wheel notches arrive"   om wheelchg 3
chk "ohci mouse: right button (bit 1)"   om btn 2
chk "ohci mouse: relative moves"         om moves 3
chk "ohci tablet: absolute moves"        ot moves 3
chk "ohci tablet: right button"          ot btn 2
chk "ohci tablet: pointer got far"       ot x 300
chk "ohci kbd: keys"                     ok keys 3
grep -aq '^ohci: base=.* devices=1' "$T/om.txt" && ok "ohci enumerated the mouse" || bad "ohci enumeration"
echo "== counter-proof (driver not started)"
[ "$(fld on wheelchg)" = 0 ] && [ "$(fld on btn)" = 0 ] && ok "no wheel/button without the driver" || bad "input arrived without the driver"
! grep -aq '^ohci: base=' "$T/on.txt" && ok "no ohci line without the words" || bad "ohci started without the words"
echo "== xHCI"
chk "xhci mouse: wheel"   xm wheelchg 3
chk "xhci mouse: right"   xm btn 2
chk "xhci tablet: moves"  xt moves 3
chk "xhci tablet: right"  xt btn 2
chk "xhci kbd: keys"      xk keys 3
echo "== EHCI (gap, NOTE only)"
chk "ehci mouse: wheel"   em wheelchg 3 note
echo "usbhid: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
