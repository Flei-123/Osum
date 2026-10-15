#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wlan-ax201-glue/run.sh -- W-AX201 M1b: kernel glue (kernel/drv/net/iwl.fi), MEASURED in QEMU.
#
#   bash tools/wlan-ax201-glue/run.sh
#
# QEMU has no Intel 8086:a0f0, so the path "device present, CSRs read" can
# only run on the real laptop (see reports/TESTANLEITUNG-LAPTOP.md). What this
# gate proves WITHOUT the device:
#   - the kernel with the glue builds and boots
#   - serial line "iwl: no device" (clean path, nothing mapped)
#   - /proc/wlan exists and says "none"; sysinfo has a "wlan" section
#   - a PCI device that is NOT an Intel WLAN (edu, 1234:11e8, 1 MiB BAR0) is
#     left alone: still "iwl: no device", boot continues
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$TMPD/bin"
PROGS="sh cat echo sysinfo"
bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1 \
    && ok "programs build" || { bad "programs build"; head -20 "$TMPD/b.txt"; echo "WLAN-GLUE: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1 \
    && ok "kernel with iwl glue builds" || { bad "kernel build"; tail -20 "$TMPD/k.txt"; echo "WLAN-GLUE: $pass passed, $fail failed"; exit 1; }
cat > "$TMPD/s.sh" <<'EOS'
echo ==WLAN==
cat /proc/wlan
echo ==REPORT==
sysinfo
echo ==END==
EOS
python3 tools/osum/mkfs.py build "$TMPD/d.img" 20000 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ /var/crash/ \
    $(for p in $PROGS; do echo "/bin/$p=$TMPD/bin/$p.elf"; done) \
    "/t/s.sh=$TMPD/s.sh" > "$TMPD/mkfs.txt" 2>&1 || tail -3 "$TMPD/mkfs.txt"
run() { # name extra-qemu-args...
    local n="$1"; shift
    timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 \
        -kernel "$TMPD/k0.img" -m 512 "$@" \
        -append "osum vfs script=sh /t/s.sh;exit" \
        -serial "file:$TMPD/$n.txt" -display none -no-reboot \
        -drive "file=$TMPD/d.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$TMPD/$n.txt" > "$TMPD/$n.klar"
    part "$TMPD/$n.klar" WLAN REPORT > "$TMPD/$n.wlan"
    part "$TMPD/$n.klar" REPORT END > "$TMPD/$n.rep"
}
echo "-- A: plain machine, no WLAN"
run a
has "$TMPD/a.klar" "iwl: no device" "serial: iwl: no device"
hasnot "$TMPD/a.klar" "iwl: hw_rev" "serial: no invented hw_rev"
has "$TMPD/a.wlan" "none" "/proc/wlan says none"
has "$TMPD/a.rep" "== wlan ==" "sysinfo has the wlan section"
has "$TMPD/a.rep" "none" "sysinfo wlan section says none"
has "$TMPD/a.rep" "== usb ==" "sysinfo still prints the sections after wlan"
echo "-- B: foreign PCI device with a big BAR0 (edu), must be left alone"
run b -device edu
has "$TMPD/b.klar" "iwl: no device" "serial: edu is not a WLAN: no device"
has "$TMPD/b.klar" "1234:11e8" "the edu device really is on the bus (/proc/pci not needed: pci list)"
has "$TMPD/b.wlan" "none" "/proc/wlan none with a foreign device"
has "$TMPD/b.rep" "== wlan ==" "sysinfo works with the foreign device"
echo "WLAN-GLUE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
