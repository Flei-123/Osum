#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/blchain/run.sh -- backlight fallback chain gate (ACPI _BCM -> Intel PWM -> soft) with counter-proofs. BLCHAIN_IMG=<osum.mb> skips the build.
set -uo pipefail
cd "$(dirname "$0")/../.."
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
OK=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then OK=$((OK+1)); printf '  ok    %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL  %s: want <%s> got <%s>\n' "$1" "$2" "$3"; fi; }
. tools/lib/qemu.sh 2>/dev/null
if [ -n "${BLCHAIN_IMG:-}" ]; then IMG=$BLCHAIN_IMG; else IMG="$D/osum.mb"; ./tools/build-kernel.sh "$IMG" > /dev/null || { echo "build failed"; exit 1; }; fi
[ -f tools/blchain/asl/other.aml ] || ( cd tools/blchain/asl && iasl other.asl > /dev/null 2>&1 )
run() { # name words [table]
    local t=(); [ -n "${3:-}" ] && t=(-acpitable "file=$3")
    timeout 60 ${QEMU_X86:-qemu-system-x86_64} -kernel "$IMG" -m 256 -append "acpiev evself $2 nokbd noring3 nofs" "${t[@]}" \
        -serial "file:$D/$1.txt" -display none -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    echo $?
}
g() { grep -ac "$2" "$D/$1.txt"; }
echo "== 1. PCH layout PWM"
chk "run ends cleanly" 21 "$(run pch blpch)"
chk "stage: src=2 pwm=1 lay=1" 1 "$(g pch 'blchain: src2 pct=60 pwm=1 why=0 lay=1')"
chk "100 -> 100 (twice)" 2 "$(g pch 'test p100 src=2 back=100')"
chk "50 -> 50" 1 "$(g pch 'test p50 src=2 back=50')"
chk "0 -> floor 5 (never black)" 1 "$(g pch 'test p0 src=2 back=5')"
chk "Notify 0x86 up 50 -> 60" 1 "$(g pch 'key u60')"
chk "Notify 0x87 down twice -> 40" 1 "$(g pch 'key d40')"
chk "ext hotkey up -> 50" 1 "$(g pch 'ext u50')"
echo "== 2. CPU layout PWM"
chk "run ends cleanly" 21 "$(run cpu blcpu)"
chk "stage: lay=2" 1 "$(g cpu 'pwm=1 why=0 lay=2')"
chk "50 -> 50" 1 "$(g cpu 'test p50 src=2 back=50')"
echo "== 3. counter-proofs"
chk "implausible period refused (why=5)" 1 "$(run bad 'blpch blbad' >/dev/null; g bad 'pwm=0 why=5 lay=0')"
chk "refused: no write reaches a source" 0 "$(g bad 'src=2')"
chk "blnone: PWM way off (why=6)" 1 "$(run none blnone >/dev/null; g none 'pwm=0 why=6')"
chk "no device, no word: nothing probed, no hang" 21 "$(run bare '')"
echo "== 4. _BCM at another path (DD1F), PWM present, _BCM has no effect"
chk "run ends cleanly" 21 "$(run oth blpch tools/blchain/asl/other.aml)"
chk "ACPI found under PCI0.GFX0.DD1F" 1 "$(g oth 'acpibl: levels=11')"
chk "no-effect detected, PWM takes over" 1 "$(g oth 'test p50 src=2 back=50')"
echo "== 5. _BCM at another path, no PWM: ACPI is used"
chk "run ends cleanly" 21 "$(run oth2 blnone tools/blchain/asl/other.aml)"
chk "src=1 after ACPI write" 1 "$(g oth2 'test p50 src=1 back=50')"
echo; echo "blchain: $OK ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
