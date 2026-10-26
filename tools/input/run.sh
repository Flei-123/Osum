#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# usage: bin/heavy bash tools/input/run.sh   (INPUT_IMG=<kernel image> skips the kernel build; docs/INPUT.md section 9)
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
export PYTHONDONTWRITEBYTECODE=1
. tools/lib/qemu.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
sub() { # name command...   (sub-gate prints a summary line; its exit code decides)
    local name=$1; shift
    if "$@" > "$T/$name.log" 2>&1; then ok "$name: $(tail -1 "$T/$name.log")"; else bad "$name: $(tail -1 "$T/$name.log")"; grep -a -E '^\s*FAIL|FAIL ' "$T/$name.log" | head -8 | sed 's/^/        /'; fi
}

echo "== 1. host libs =="
sub touchgest bash tools/touchgest/run.sh
sub touchev bash tools/touchev/run.sh

echo "== 2. corpus =="
sub corpus python3 -I tools/input/check_corpus.py
sub corpus-selftest python3 -I tools/input/check_corpus.py --selftest
sub corpus-kernel-data python3 -I tools/input/corpus_kernel.py check-gen

echo "== 3. kernel =="
IMG=${INPUT_IMG:-}
if [ -z "$IMG" ]; then
    IMG="$T/osum.mb"
    if bash tools/build-kernel.sh "$IMG" > "$T/build.log" 2>&1; then ok "kernel builds"; else bad "kernel build failed"; tail -5 "$T/build.log" | sed 's/^/        /'; echo "input: $pass ok, $fail fail"; exit 1; fi
fi
timeout 90 $QEMU_X86 -kernel "$IMG" -m 256 -append "touchsim nokbd noring3 nofs" -serial "file:$T/sim.txt" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
RC=$?
[ "$RC" = 21 ] && ok "touchsim boot ends cleanly (21)" || bad "touchsim boot exit code $RC (want 21)"
S="$T/sim.txt"
sub touchsim env TOUCHSIM_IMG="$IMG" bash tools/touchsim/run.sh
if python3 -I tools/input/corpus_kernel.py compare "$S" > "$T/cmp.log" 2>&1; then ok "corpus replay: $(tail -1 "$T/cmp.log")"; else bad "corpus replay: $(tail -1 "$T/cmp.log")"; grep -a -E '^FAIL|^   [!]' "$T/cmp.log" | head -14 | sed 's/^/        /'; fi
n() { grep -ac "$1" "$S"; }
eq() { [ "$2" = "$3" ] && ok "$1 ($3)" || bad "$1: want $2, got $3"; }
echo "-- sim ring (touchsim phases before the corpus run)"
SIMRING=$(sed -n '/^touchsim: end /,/^corpus: begin dev0/p' "$S")
cnt() { printf '%s\n' "$SIMRING" | grep -ac "$1"; }
eq "touch screen contacts: 5 DOWN (tap, drag, 2 scroll fingers, long press)" 5 "$(cnt '^touchev: 1 slot=[0-9] dev=1 ')"
eq "touch screen contacts: 5 UP" 5 "$(cnt '^touchev: 3 slot=[0-9] dev=1 ')"
eq "pen: hover DOWN, two MOVE, UP when out of range" "1 2 1" "$(cnt '^touchev: 1 slot=0 dev=3 ') $(cnt '^touchev: 2 slot=0 dev=3 ') $(cnt '^touchev: 3 slot=0 dev=3 ')"
eq "gesture records: one tap" 1 "$(cnt '^touchev: 4 slot=255 dev=1 fl=1 ')"
eq "gesture records: one long press" 1 "$(cnt '^touchev: 4 slot=255 dev=1 fl=2 ')"
eq "gesture records: one drag begin" 1 "$(cnt '^touchev: 4 slot=255 dev=1 fl=3 ')"
eq "gesture records: one drag end" 1 "$(cnt '^touchev: 4 slot=255 dev=1 fl=5 ')"
echo "-- registry lines (/proc/inputdevs)"
eq "inputdevs: touch pad line carries vid, pid, bus, quirks" 1 "$(n '^inputdevs: hid3 kind=4 vid=0x04f3 pid=0x3003 bus=2 q=0x00')"
eq "inputdevs: touch screen line" 1 "$(n '^inputdevs: hid4 kind=16 vid=0x04f3 pid=0x2a01 bus=2 q=0x00')"
eq "inputdevs: pen line" 1 "$(n '^inputdevs: hid5 kind=32 vid=0x056a pid=0x5002 bus=2 q=0x00')"
eq "inputdevs: the Surface touch screen id 045e:0c32 got the single-touch quirk from the table" 1 "$(n '^inputdevs: hid0 kind=16 vid=0x045e pid=0x0c32 bus=2 q=0x10')"

echo "== 4. end to end =="
sub e2e bash tools/input/e2e.sh "$IMG"

echo "input: $pass ok, $fail fail"
[ "$fail" = 0 ]
