#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Usage: bash tools/highframe/run.sh [new-kernel.mb] [old-kernel.mb]
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

MEM=${HIGHFRAME_MEM:-3072}
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', expected '$3'"; fi; }
has() { grep -qaE -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaE -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "HIGHFRAME: skipped, qemu missing"; exit 0; }

echo "== 1. build =="
NEW=${1:-}
OLD=${2:-}
if [ -z "$NEW" ]; then
    NEW="$D/new.mb"
    bash tools/build-kernel.sh "$NEW" > "$D/build.txt" 2>&1 \
        && ok "kernel builds" || { bad "kernel build failed"; tail -5 "$D/build.txt"; exit 1; }
fi
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 sh echo hifr > "$D/ubuild.txt" 2>&1 \
    && ok "user programs build" || { bad "user programs build failed"; exit 1; }
printf 'PATTERN\n' > "$D/pat"
cat > "$D/s.sh" <<'SCRIPT'
echo ==SMALL==
hifr 400
echo ==BIG==
hifr 1500
echo ==AFTER==
hifr 100
echo ==END==
SCRIPT
python3 tools/osum/mkfs.py build "$D/p.img" 20000 /bin/ /etc/ /run/ /tmp/ /t/ /proc/ /dev/ /system/ /var/ \
    "/bin/sh=$D/bin/sh.elf" "/bin/echo=$D/bin/echo.elf" "/bin/hifr=$D/bin/hifr.elf" \
    "/t/pat=$D/pat" "/t/s.sh=$D/s.sh" > "$D/mkfs.txt" 2>&1 \
    && ok "disk image built" || { bad "mkfs failed"; exit 1; }

run_case() {
    local name=$1 kern=$2
    cp "$D/p.img" "$D/live-$name.img"
    timeout 280 $QEMU_X86 -kernel "$kern" -m "$MEM" \
        -append "osum vfs nokbd nosched script=sh /t/s.sh;exit" \
        -serial "file:$D/$name.txt" -display none -no-reboot \
        -drive "file=$D/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    echo $?
}
clean() { tr -cd '\11\12\15\40-\176' < "$1" | tr -d '\r' > "$1.clean"; }
part() { sed -n "/^==$2==\$/,/^==$3==\$/p" "$1.clean"; }

echo "== 2. fixed kernel: user frames stay reachable in process context =="
rc=$(run_case new "$NEW")
F="$D/new.txt"; clean "$F"
has "$F.clean" "mem: process context reaches frames < 262144" "kernel confines frames at the first process"
hasnot "$F.clean" "EXCEPTION" "no kernel page fault"
hasnot "$F.clean" "ABSTURZBERICHT" "no crash report"
is "kernel finished" "$rc" "21"
is "400 MiB touched" "$(part "$F" SMALL BIG | grep -ac '^hifr: touched 102400$')" "1"
is "write from a user page reads right" "$(part "$F" SMALL BIG | grep -ac '^HIFR-WRITE-OK$')" "1"
is "read into a user page lands right" "$(part "$F" SMALL BIG | grep -ac '^hifr: read ok$')" "1"
is "1500 MiB does not complete" "$(part "$F" BIG AFTER | grep -ac '^hifr: end$')" "0"
is "the hog is killed cleanly (user fault)" "$(part "$F" BIG AFTER | grep -ac 'user fault: .*process killed')" "1"
is "memory is back afterwards" "$(part "$F" AFTER END | grep -ac '^hifr: end$')" "1"

echo "== 3. counter-proof: kernel without the fix =="
if [ -n "$OLD" ]; then
    rc=$(run_case old "$OLD")
    F="$D/old.txt"; clean "$F"
    has "$F.clean" "EXCEPTION 14" "old kernel faults"
    has "$F.clean" "proc\.(lazy_fault|map_page_zero|zero_frame)|sys\.copy_(in|out)" "inside the user frame touch"
    hasnot "$F.clean" "mem: process context reaches" "old kernel has no confinement"
else
    echo "  skip  no old kernel given"
fi

[ -n "${HIGHFRAME_KEEP:-}" ] && cp "$D"/new.txt "$D"/old.txt "$HIGHFRAME_KEEP"/ 2>/dev/null
echo "highframe: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
