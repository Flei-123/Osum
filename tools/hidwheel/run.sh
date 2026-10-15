#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hidwheel/run.sh -- r804: HORIZONTAL WHEEL + SWIPE AS WINDOW SWITCH in the window server.
#
# WHAT IT MEASURES (QEMU, window server up, word `hwheeltest` = wm.hw_demo, lines `hw:`):
#   1. two horizontal steps to the right over window a: ONE E_HWHEEL (type 10), notches c = 2, only a gets it;
#   2. one step left: c = 0xFFFF (-1, 16-bit two's complement);
#   3. over the gap between the windows: the sum is taken, nobody gets an event;
#   4. over window b: b gets it, a does not;
#   5. 3-finger swipe left = other window, right = back; 2 fingers and swipe up = nothing.
# COUNTER-CONTROL: without the word no `hw:` line appears.
#
# Usage: [HW_KERNEL=<kernel.mb>] bash tools/hidwheel/run.sh   (builds its own kernel when unset)
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh >/dev/null 2>&1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
K=${HW_KERNEL:-$T/k.mb}
if [ -z "${HW_KERNEL:-}" ]; then
    bash tools/build-kernel.sh "$K" >"$T/build.log" 2>&1 || { echo "build failed"; tail -20 "$T/build.log"; exit 1; }
fi
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -aq "$1" "$T/$2.txt"; }

python3 tools/osum/mkfs.py build "$T/d.img" 32768 --v3 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf >/dev/null 2>&1

run_case() { # run_case <tag> <kernel words>
    local tag=$1 words=$2
    cp -f "$T/d.img" "$T/$tag.img"
    timeout 120 $QEMU_X86 -kernel "$K" -m 256 \
        -append "gfx disp wm wmhold osum vfs $words nokbd" \
        -serial "file:$T/$tag.txt" -display none -no-reboot \
        -vga std -drive "file=$T/$tag.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}

echo "== hwheeltest"
run_case hw "hwheeltest"
grep -a '^hw: ' "$T/hw.txt" | sed 's/^/   /'
has '^hw: right2 on-a type=10 c=0x2' hw && ok "two steps right -> one E_HWHEEL (10) with c=2 to window a" || bad "right2"
has '^hw: left1 on-a type=10 c=0xffff' hw && ok "one step left -> c=0xFFFF (-1)" || bad "left1"
has '^hw: gap no-win empty$' hw && ok "over the gap: window a gets nothing" || bad "gap a"
[ "$(grep -ac '^hw: gap no-win empty$' "$T/hw.txt")" = 2 ] && ok "over the gap: window b gets nothing either" || bad "gap b"
has '^hw: right1 on-b type=10 c=0x1' hw && ok "over window b: b gets E_HWHEEL c=1" || bad "right1 on b"
has '^hw: on-a after  empty$' hw && ok "window a got nothing from the step over b" || bad "a after b"
has '^hw: swipe left moved=1 focus=' hw && ok "swipe left (3 fingers) moves the focus" || bad "swipe left"
has '^hw: swipe right moved=1 focus=a$' hw && ok "swipe right (3 fingers) goes back to window a" || bad "swipe right"
has '^hw: swipe 2 fin moved=0 focus=a$' hw && ok "2 fingers: no window switch" || bad "swipe 2 fingers"
has '^hw: swipe up moved=0 focus=a$' hw && ok "swipe up: no consumer, focus stays" || bad "swipe up"

echo "== counter-control: no word"
run_case none ""
! has '^hw: ' none && ok "without hwheeltest no hw: line" || bad "hw: line without the word"

echo "wheel: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
