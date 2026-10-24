#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ps2gone/run.sh -- r1769: board without an i8042 (status port reads 0xFF). PS2GONE_IMG=<osum.mb> skips the build.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
export FIRNLIB="$PWD/lib"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
OK=0; FAIL=0
eq() { if [ "$2" = "$3" ]; then OK=$((OK+1)); printf '  ok    %s (%s)\n' "$1" "$3"; else FAIL=$((FAIL+1)); printf '  FAIL  %s: want <%s> got <%s>\n' "$1" "$2" "$3"; fi; }
if [ -n "${PS2GONE_IMG:-}" ]; then IMG=$PS2GONE_IMG; else IMG="$D/osum.mb"; ./tools/build-kernel.sh "$IMG" > /dev/null || { echo "build failed"; exit 1; }; fi
run() {
    timeout 45 $QEMU_X86 -kernel "$IMG" -m 256 -append "$2" -serial "file:$D/$1.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    echo $?
}
g() { grep -ac "$2" "$D/$1.txt"; }
echo "== 1. ps2gone: init stops at once"
W="modul nokbd noring3 nofs"
run gone "ps2gone $W" > /dev/null
eq "both module inits stop with the no-controller line (vor + nach)" 2 "$(g gone 'ps2m: no i8042')"
eq "no kernel exception" 0 "$(g gone EXCEPTION)"
echo "== 2. counter-proof: without the word the mouse starts"
run base "$W" > /dev/null
eq "module init ran and reported" 2 "$(g base '^modul: [a-z]* init=')"
eq "no no-controller line" 0 "$(g base 'ps2m: no i8042')"
echo; echo "ps2gone: $OK ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
