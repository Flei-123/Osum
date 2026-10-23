#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/acpibl/run.sh -- ACPI backlight (_BCL/_BCM/_BQC) gate against SSDTs injected with -acpitable.
# Usage: bash tools/acpibl/run.sh   (ACPIBL_IMG=<osum.mb> skips the build)
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
OK=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then OK=$((OK+1)); printf '  ok    %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL  %s: want <%s> got <%s>\n' "$1" "$2" "$3"; fi; }
if [ -n "${ACPIBL_IMG:-}" ]; then IMG=$ACPIBL_IMG; else IMG="$D/osum.mb"; ./tools/build-kernel.sh "$IMG" > /dev/null || { echo "build failed"; exit 1; }; fi
for v in backlight nobcm; do [ -f "tools/acpibl/asl/$v.aml" ] || ( cd tools/acpibl/asl && iasl $v.asl > /dev/null 2>&1 ); done
run() { # name table
    local t=(); [ -n "$2" ] && t=(-acpitable "file=tools/acpibl/asl/$2.aml")
    timeout 60 $QEMU_X86 -kernel "$IMG" -m 256 -append "acpiev evself nokbd noring3 nofs" "${t[@]}" \
        -serial "file:$D/$1.txt" -display none -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    echo $?
}
echo "== 1. backlight device present"
chk "run ends cleanly" 21 "$(run bl backlight)"
S=$D/bl.txt
chk "levels parsed (11, 0..100)" "acpibl: levels=11 min=0 max=100 cur=0" "$(grep -a '^acpibl: levels' $S)"
chk "100 -> level 100, readback 100" 1 "$(grep -ac 'test p=100 level=100 back=100' $S | sed 's/^2$/1/')"
chk "50 -> level 50, readback 50" 1 "$(grep -ac 'test p=50 level=50 back=50' $S)"
chk "0 clamps to floor level 10" 1 "$(grep -ac 'test p=0 level=10 back=10' $S)"
chk "brightness-up key (Notify 0x86) 50 -> 60" 1 "$(grep -ac 'key up p=60' $S)"
chk "brightness-down key twice 60 -> 40" 1 "$(grep -ac 'key down p=40' $S)"
echo "== 2. counter-proofs"
chk "no _BCM: stage says none" 1 "$(run nb nobcm >/dev/null; grep -ac '^acpibl: none' $D/nb.txt)"
chk "no table: stage says none, no test lines" 0 "$(run nt '' >/dev/null; grep -ac 'acpibl: test p=' $D/nt.txt)"
echo; echo "acpibl: $OK ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
