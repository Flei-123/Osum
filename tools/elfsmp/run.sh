#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/elfsmp/run.sh -- r334: THE ELF LOADER IS SMP-SAFE.
#
#   bash tools/elfsmp/run.sh [<runs per variant>] [<cores>]
#
# Before: `elf.load` shared ONE header buffer (kstate.ELF_OFF) plus the
# interpreter/auxv slots between all cores. Two cores starting programs at
# once (the login screen and the taskbar at boot) mixed up their program
# headers; `glogin` was refused with 'reason 17 two segments one page' and
# the login screen never came up (VM, 4 cores: 4 of 4 boots).
# After: one lock (`elf.lock_enter`) around every program start.
#
# Measures, on the stick image (4 cores by default):
#   fix      N boots: every one must print `glogin: bereit` and no
#            'elf: refused' line may show up
#   counter  N boots with the kernel word `noelflock` (lock off): at least
#            one boot must show the old failure -- otherwise the test
#            would measure nothing
set -uo pipefail
cd "$(dirname "$0")/../.."
RUNS=${1:-6}
CORES=${2:-4}
TMPD=$(mktemp -d /tmp/elfsmp.XXXXXX)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

echo "== build the stick =="
if UITRACE=1 PARTTAB=mbr bash tools/usbimg/build.sh "$TMPD/b" > "$TMPD/build.log" 2>&1; then
    ok "stick built"
else
    tail -15 "$TMPD/build.log"; bad "the build failed"; echo "ELFSMP: $pass passed, $fail failed"; exit 1
fi
IMG="$TMPD/b/orientos-usb.img"
KVM=(-accel tcg)
[ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)

boot() { # boot <name> <extra kernel word or empty>  -> echoes ok|bad
    local name=$1 extra=$2
    local D="$TMPD/$name"
    mkdir -p "$D"
    cp -f "$IMG" "$D/stick.img"
    local off=$((2048 * 512))
    mcopy -o -i "$D/stick.img@@$off" ::/limine.conf "$D/l.conf" || { echo bad; return; }
    sed -i 's/^timeout: .*/timeout: 1/' "$D/l.conf"
    [ -n "$extra" ] && sed -i "s/^\( *cmdline: .*\)\$/\1 $extra/" "$D/l.conf"
    mcopy -o -i "$D/stick.img@@$off" "$D/l.conf" ::/limine.conf
    timeout 200 qemu-system-x86_64 "${KVM[@]}" -m 2048 -smp "$CORES" \
        -device qemu-xhci,id=xhci \
        -drive if=none,id=stick,format=raw,file="$D/stick.img" \
        -device usb-storage,bus=xhci.0,drive=stick,bootindex=1 \
        -device usb-kbd,bus=xhci.0 -device usb-mouse,bus=xhci.0 \
        -netdev user,id=n0 -device e1000e,netdev=n0 \
        -vga std -display none -no-reboot \
        -serial file:"$D/serial.txt" > "$D/qemu.txt" 2>&1 &
    local pid=$! i=0
    while [ $i -lt 120 ]; do
        grep -qa 'glogin: bereit' "$D/serial.txt" 2>/dev/null && break
        grep -qa 'elf: refused' "$D/serial.txt" 2>/dev/null && break
        sleep 1; i=$((i + 1))
    done
    sleep 2
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    if grep -qa 'glogin: bereit' "$D/serial.txt" && ! grep -qa 'elf: refused' "$D/serial.txt"; then
        echo ok
    else
        grep -a '^elf: refused' "$D/serial.txt" | head -2 >&2
        echo bad
    fi
    rm -rf "$D"
}

echo "== fix: $RUNS boots, $CORES cores =="
good=0
for n in $(seq 1 "$RUNS"); do
    r=$(boot "fix$n" "")
    echo "        boot $n: $r"
    [ "$r" = ok ] && good=$((good+1))
done
[ "$good" -eq "$RUNS" ] && ok "login screen up in $good of $RUNS boots" \
    || bad "login screen up in only $good of $RUNS boots"

echo "== counter-proof: noelflock, $RUNS boots =="
broken=0
for n in $(seq 1 "$RUNS"); do
    r=$(boot "cnt$n" "noelflock")
    echo "        boot $n: $r"
    [ "$r" = bad ] && broken=$((broken+1))
done
[ "$broken" -ge 1 ] && ok "without the lock the old failure shows in $broken of $RUNS boots" \
    || bad "without the lock no boot failed -- the test measures nothing"

echo; echo "ELFSMP: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
