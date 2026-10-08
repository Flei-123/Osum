#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/stab/flush.sh -- the I219 descriptor-ring flush (kernel/drv/net/e1000.fi,
# flush_desc_rings) on what QEMU can show.
#
#   bash tools/stab/flush.sh
#
# QEMU has no I219, and its 82574 never sets PCI config 0xE4 bit 8. The kernel
# word `nicflush` (with `nicich`, the PCH bring-up on the 82574) forces the
# sequence; what a model CAN show is checked:
#   * the sequence runs before the reset and the card still comes up (a ping is
#     not needed: the "e1000: up" line and the rings after it)
#   * TX: the dummy descriptor was consumed -- TDH moved to 1, TDT is 1
#   * RX: RXDCTL(0) holds prefetch threshold 31, host threshold 1, granularity
#     descriptors (low 14 bits 0x11F, bit 24)
#   * without `nicflush` NOTHING of that is printed (the I217/82574 path is
#     unchanged), and FEXTNVM11 is not touched
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/b.txt" 2>&1 || { tail -5 "$T/b.txt"; echo "FLUSH: build failed"; exit 1; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
run() { # <name> <words>
    timeout 120 qemu-system-x86_64 -accel $ACC -kernel "$T/k.img" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 nic nicich $2 nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=10" \
        -serial "file:$T/$1.txt" -display none -no-reboot \
        -netdev user,id=n0 -device e1000e,netdev=n0,mac=52:54:00:aa:bb:cc \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$1.txt" > "$T/$1.klar"
}
run plain ""
run flush "nicflush"
P="$T/plain.klar"; F="$T/flush.klar"
grep -aq "e1000: up" "$P" && ok "plain: the card comes up as before" || bad "plain: no 'e1000: up'"
grep -aq "flush:" "$P" && bad "plain: flush lines printed without nicflush" || ok "plain: no flush lines without nicflush (82574 path unchanged)"
grep -aq "e1000: up" "$F" && ok "nicflush: the card still comes up after the flush" || bad "nicflush: no 'e1000: up'"
grep -aq "flush: required" "$F" && ok "nicflush: the flush is entered" || bad "nicflush: not entered"
l=$(grep -a "flush: tx dummy" "$F" | head -1)
echo "        $l"
echo "$l" | grep -aqE "0x0*10001$" && ok "TX: dummy descriptor consumed (TDH = 1, TDT = 1)" || bad "TX: head/tail not 1/1"
l=$(grep -a "e1000:      rxdctl" "$F" | head -1)
echo "        $l"
python3 - "$l" <<'P' && ok "RX: RXDCTL(0) = pthresh 31, hthresh 1, granularity descriptors" || bad "RX: RXDCTL(0) wrong"
import re, sys
m = re.search(r"0x([0-9a-fA-F]+)", sys.argv[1])
v = int(m.group(1), 16) if m else 0
sys.exit(0 if (v & 0x3F) == 0x1F and ((v >> 8) & 0x3F) == 1 and (v >> 24) & 1 else 1)
P
echo "FLUSH: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
