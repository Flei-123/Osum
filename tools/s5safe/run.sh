#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Usage: bash tools/s5safe/* [new-kernel.img] [old-kernel.img]
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
MEM=${S5SAFE_MEM:-3072}
PROGS="sh echo reboot shutdown"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', expected '$3'"; fi; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "S5SAFE: skipped, qemu-system-x86_64 missing"
    exit 0
fi

echo "== 1. build =="
NEW=${1:-}
OLD=${2:-}
if [ -z "$NEW" ]; then
    NEW="$TMPD/new.img"
    bash tools/build-kernel.sh "$NEW" --stufe 0 > "$TMPD/build.txt" 2>&1 \
        && ok "kernel builds" || { bad "kernel build failed"; tail -5 "$TMPD/build.txt"; exit 1; }
fi
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s does not assemble"
SPEC=""
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" >"$TMPD/e$p" 2>&1 \
        && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
            -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null \
        || { bad "cannot build $p"; head -5 "$TMPD/e$p"; exit 1; }
    strip --strip-all "$TMPD/$p.elf"
    SPEC="$SPEC /bin/$p=$TMPD/$p.elf"
done
printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
python3 tools/osum/mkfs.py build "$TMPD/disk.img" 16384 /bin/ /etc/ /run/ $SPEC \
    /etc/passwd="$TMPD/passwd"@644:0:0 > "$TMPD/mkfs.txt" 2>&1 \
    && ok "disk image built" || { bad "mkfs failed"; head -5 "$TMPD/mkfs.txt"; exit 1; }

run_case() {
    local name=$1 kern=$2 app=$3
    cp "$TMPD/disk.img" "$TMPD/live-$name.img"
    timeout 240 $QEMU_X86 -kernel "$kern" -m "$MEM" -append "$app" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    echo $?
}

BASE="osum initsh nokbd nosched noproc nofs noring3"

echo "== 2. poweroff with the tables above the first GiB =="
rc=$(run_case off "$NEW" "$BASE script=echo ==BEGIN==;shutdown -f;echo ==END==")
F="$TMPD/off.txt"
has "$F" "==BEGIN==" "script ran"
hasnot "$F" "EXCEPTION" "poweroff does not fault"
hasnot "$F" "ABSTURZBERICHT" "poweroff leaves no crash report"
has "$F" "power: acpi" "poweroff reached the ACPI path"
is "machine powered off through ACPI" "$rc" "0"

echo "== 3. reboot with the tables above the first GiB =="
rc=$(run_case reboot "$NEW" "$BASE script=echo ==BEGIN==;reboot -f;echo ==END==")
F="$TMPD/reboot.txt"
has "$F" "==BEGIN==" "script ran"
hasnot "$F" "EXCEPTION" "reboot does not fault"
hasnot "$F" "ABSTURZBERICHT" "reboot leaves no crash report"
hasnot "$F" "power: acpi pm1a" "reboot never writes the S5 sleep type"
has "$F" "power: reset" "reboot went through the reset chain"
is "machine reset (QEMU exits on reset with -no-reboot)" "$rc" "0"

if [ -n "$OLD" ]; then
    echo "== 4. counter-check: the old kernel faults =="
    rc=$(run_case oldoff "$OLD" "$BASE script=echo ==BEGIN==;shutdown -f;echo ==END==")
    F="$TMPD/oldoff.txt"
    if grep -aqE "EXCEPTION|ABSTURZBERICHT|vektor 14" "$F" || [ "$rc" != "0" ]; then
        ok "old kernel does not power off cleanly (rc=$rc)"
    else
        bad "old kernel powered off cleanly -- the gate does not reproduce the bug"
    fi
    grep -aqE "EXCEPTION|ABSTURZBERICHT|vektor 14" "$F" \
        && ok "old kernel faults on poweroff" \
        || bad "old kernel did not fault (rc=$rc)"
fi

echo "S5SAFE: $pass passed, $fail failed"
[ "$fail" = 0 ]
