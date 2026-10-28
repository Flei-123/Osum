#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Usage: bash tools/amlmem/run.sh [new-kernel.mb] [old-kernel.mb]
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

MEM=${AMLMEM_MEM:-3072}
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', expected '$3'"; fi; }
has() { grep -qaE -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaE -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "AMLMEM: skipped, qemu missing"; exit 0; }
command -v iasl >/dev/null 2>&1 || { echo "AMLMEM: skipped, iasl missing"; exit 0; }

echo "== 1. build =="
NEW=${1:-}
OLD=${2:-}
if [ -z "$NEW" ]; then
    NEW="$D/new.mb"
    bash tools/build-kernel.sh "$NEW" > "$D/build.txt" 2>&1 \
        && ok "kernel builds" || { bad "kernel build failed"; tail -5 "$D/build.txt"; exit 1; }
fi
iasl -p "$D/mem" tools/amlmem/mem.asl > "$D/iasl.txt" 2>&1 && ok "ssdt compiles" || { bad "ssdt build failed"; exit 1; }
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 sh echo sleep dispctl > "$D/ubuild.txt" 2>&1 \
    && ok "user programs build" || { bad "user programs build failed"; exit 1; }
cat > "$D/s.sh" <<'SCRIPT'
sleep -m 800
echo ==READ==
dispctl
echo ==END==
SCRIPT
python3 tools/osum/mkfs.py build "$D/p.img" 20000 /bin/ /etc/ /run/ /tmp/ /t/ /proc/ /dev/ /system/ /var/ \
    "/bin/sh=$D/bin/sh.elf" "/bin/echo=$D/bin/echo.elf" "/bin/sleep=$D/bin/sleep.elf" "/bin/dispctl=$D/bin/dispctl.elf" \
    "/t/s.sh=$D/s.sh" > "$D/mkfs.txt" 2>&1 \
    && ok "disk image built" || { bad "mkfs failed"; exit 1; }

REGION=0xA0000000
run_case() {
    local name=$1 kern=$2
    shift 2
    cp "$D/p.img" "$D/live-$name.img"
    timeout 240 $QEMU_X86 -kernel "$kern" -m "$MEM" \
        -append "osum vfs nokbd nosched acpiev disp script=sh /t/s.sh;exit" \
        -serial "file:$D/$name.txt" -display none -no-reboot "$@" \
        -drive "file=$D/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    echo $?
}

clean() { tr -cd '\11\12\15\40-\176' < "$1" | tr -d '\r' > "$1.clean"; }
read_part() { sed -n '/^==READ==$/,/^==END==$/p' "$1.clean"; }
PRELOAD=(-acpitable "file=$D/mem.aml" -device "loader,addr=$REGION,data=0x32,data-len=1")

echo "== 2. process-context AML reads a SystemMemory region above the first GiB =="
rc=$(run_case new "$NEW" "${PRELOAD[@]}")
F="$D/new.txt"; clean "$F"
has "$F.clean" "==READ==" "script ran"
hasnot "$F.clean" "EXCEPTION" "no page fault"
hasnot "$F.clean" "ABSTURZBERICHT" "no crash report"
is "kernel finished after the read" "$rc" "21"
has "$F.clean" "acpibl: levels=11 min=0 max=100 cur=50" "boot-time read sees the preloaded byte"
is "ring-3 read through the window equals it" "$(read_part "$F" | grep -ac '^dispctl: bright=100$')" "1"

echo "== 3. counter-proof: kernel without the fix =="
if [ -n "$OLD" ]; then
    rc=$(run_case old "$OLD" "${PRELOAD[@]}")
    F="$D/old.txt"; clean "$F"
    has "$F.clean" "EXCEPTION 14" "old kernel faults"
    has "$F.clean" "cr2=0xa0000000" "at the region address"
    has "$F.clean" "acpibl\.query" "inside the AML region read"
else
    echo "  skip  no old kernel given"
fi

echo "== 4. counter-proof: no table =="
rc=$(run_case none "$NEW")
F="$D/none.txt"; clean "$F"
hasnot "$F.clean" "EXCEPTION" "no fault without the table"
is "no bright=100 without the table" "$(read_part "$F" | grep -ac '^dispctl: bright=100$')" "0"
is "kernel finished" "$rc" "21"

[ -n "${AMLMEM_KEEP:-}" ] && cp "$D"/new.txt "$D"/old.txt "$D"/none.txt "$AMLMEM_KEEP"/ 2>/dev/null
echo "amlmem: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
