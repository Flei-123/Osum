#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fnkeys/run.sh -- W-HW6 gate: Fn brightness keys (candidate PS/2 set-1 E0 codes + ACPI Notify 0x85..0x88), dedupe between the two paths, unknown-code diagnostics (/proc/hotkeys, serial). HOTKEYS_IMG=<osum.mb> skips the build.
set -uo pipefail
cd "$(dirname "$0")/../.."
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
OK=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then OK=$((OK+1)); printf '  ok    %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL  %s: want <%s> got <%s>\n' "$1" "$2" "$3"; fi; }
. tools/lib/qemu.sh 2>/dev/null
if [ -n "${HOTKEYS_IMG:-}" ]; then IMG=$HOTKEYS_IMG; else IMG="$D/osum.mb"; ./tools/build-kernel.sh "$IMG" > /dev/null || { echo "build failed"; exit 1; }; fi
run() {
    timeout 90 ${QEMU_X86:-qemu-system-x86_64} -kernel "$IMG" -m 256 -append "acpiev evself blpch $2 noring3 nofs" \
        -serial "file:$D/$1.txt" -display none -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    echo $?
}
g() { grep -ac -- "$2" "$D/$1.txt"; }
echo "== 1. candidate table + ACPI path"
chk "run ends cleanly" 21 "$(run a nokbd)"
chk "HP E0 17 -> brightness up" 1 "$(g a 'hksim: ext17 up p60')"
chk "HP E0 12 -> brightness down" 1 "$(g a 'hksim: ext12 down p50')"
chk "Dell E0 06 -> up" 1 "$(g a 'hksim: ext06 up p60')"
chk "Dell E0 05 -> down" 1 "$(g a 'hksim: ext05 down p50')"
chk "unrelated E0 6C: no change" 1 "$(g a 'hksim: ext6c other p50')"
chk "release E0 97: no change" 1 "$(g a 'hksim: ext17 release p50')"
chk "key then Notify within the window: ONE step" 1 "$(g a 'hksim: dup key+acpi p60')"
chk "Notify 0x86 alone -> up" 1 "$(g a 'hksim: acpi up 86 p70')"
chk "Notify 0x88 -> minimum 5" 1 "$(g a 'hksim: acpi zero 88 p5')"
chk "Notify 0x85 cycles up" 1 "$(g a 'hksim: acpi cycle 85 p15')"
chk "unknown Notify 0x8A: no change" 1 "$(g a 'hksim: acpi other 8a p15')"
chk "plain 0x70: no change" 1 "$(g a 'hksim: plain 70 p15')"
chk "E0 6F still up (old default)" 1 "$(g a 'hksim: ext6f up 6f p25')"
echo "== 2. diagnostics"
chk "serial: unknown ext 0x6c" 1 "$(g a 'hotkey: ext 0x6c unknown')"
chk "serial: unknown acpi 0x8a" 1 "$(g a 'hotkey: acpi 0x8a unknown')"
chk "serial: unknown key 0x70" 1 "$(g a 'hotkey: key 0x70 unknown')"
chk "/proc/hotkeys: unknown count 3" 1 "$(g a '^unknown 3')"
chk "/proc/hotkeys: one rejected duplicate" 1 "$(g a '^dups 1')"
chk "/proc/hotkeys: ext 0x6c unknown line" 1 "$(g a '^ext 0x6c unknown')"
chk "/proc/hotkeys: ext 0x17 up lines (two presses)" 2 "$(g a '^ext 0x17 up')"
chk "/proc/hotkeys: acpi 0x8a unknown line" 1 "$(g a '^acpi 0x8a unknown')"
echo "== 3. counter-proof: empty tables (nohktab)"
chk "run ends cleanly" 21 "$(run b 'nokbd nohktab')"
chk "E0 17 does nothing without the table" 1 "$(g b 'hksim: ext17 up p50')"
chk "Dell E0 06 does nothing without the table" 0 "$(g b 'hksim: ext06 up p60')"
chk "E0 17 is listed as unknown (two presses)" 2 "$(g b '^ext 0x17 unknown')"
chk "ACPI path unaffected" 1 "$(g b 'hksim: acpi up 86')"
real() {
    local n=$1 extra=$2
    timeout 60 ${QEMU_X86:-qemu-system-x86_64} -kernel "$IMG" -m 256 -append "acpiev evself evwait blpch $extra noring3 nofs" \
        -serial "file:$D/$n.txt" -display none -no-reboot -monitor "unix:$D/$n.mon,server,nowait" > /dev/null 2>&1 &
    local qp=$!
    for _ in $(seq 1 40); do grep -aq 'hksim: done' "$D/$n.txt" 2>/dev/null && break; sleep 0.5; done
    sleep 1
    echo "sendkey mail" | timeout 5 socat - "unix-connect:$D/$n.mon" > /dev/null 2>&1
    sleep 3
    kill $qp 2>/dev/null; wait $qp 2>/dev/null
}
echo "== 4. real i8042 path (QEMU sendkey mail = E0 6C)"
real r ""
chk "real key press reaches the diagnostics" 2 "$(g r 'hotkey: ext 0x6c unknown')"
real rn "nokirq nokbdpoll"
chk "counter-proof (nokirq nokbdpoll): no real key arrives" 1 "$(g rn 'hotkey: ext 0x6c unknown')"
echo; echo "fnkeys: $OK ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
