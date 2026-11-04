#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Usage: bash tools/memsize/run.sh [new-kernel.mb] [old-kernel.mb]
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

SIZES=${MEMSIZE_LIST:-"2048 4096 8192"}
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', expected '$3'"; fi; }
has() { grep -qaE -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaE -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "MEMSIZE: skipped, qemu missing"; exit 0; }

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
touch_for() { local t=$(( $1 - 900 )); [ "$t" -gt 3000 ] && t=3000; echo "$t"; }
mk_script() {
    local mib=$1 count=$2
    {
        echo "echo ==INFO=="
        echo "echo ==TOUCH=="
        for _ in $(seq "$count"); do echo "hifr $mib &"; done
        echo "wait"
        echo "echo ==END=="
    } > "$D/s.sh"
}

bash tools/mkfsfi/mkfs.sh build "$D/p.img" 20000 /bin/ /etc/ /run/ /tmp/ /t/ /proc/ /dev/ /system/ /var/ \
    "/bin/sh=$D/bin/sh.elf" "/bin/echo=$D/bin/echo.elf" "/bin/hifr=$D/bin/hifr.elf" \
    "/t/pat=$D/pat" > "$D/mkfs.txt" 2>&1 \
    && ok "disk image built" || { bad "mkfs failed"; exit 1; }

run_case() {
    local name=$1 kern=$2 mem=$3
    local np=1; [ "$mem" -ge 8192 ] && np=2
    mk_script "$(touch_for "$mem")" "$np"
    cp "$D/p.img" "$D/live-$name.img"
    bash tools/mkfsfi/mkfs.sh build "$D/live-$name.img" 20000 /bin/ /etc/ /run/ /tmp/ /t/ /proc/ /dev/ /system/ /var/ \
        "/bin/sh=$D/bin/sh.elf" "/bin/echo=$D/bin/echo.elf" "/bin/hifr=$D/bin/hifr.elf" \
        "/t/pat=$D/pat" "/t/s.sh=$D/s.sh" > "$D/mkfs-$name.txt" 2>&1
    timeout ${MEMSIZE_TIMEOUT:-900} $QEMU_X86 -kernel "$kern" -m "$mem" \
        -append "osum vfs nokbd nosched script=sh /t/s.sh;exit" \
        -serial "file:$D/$name.txt" -display none -no-reboot \
        -drive "file=$D/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    echo $?
}
clean() { tr -cd '\11\12\15\40-\176' < "$1" | tr -d '\r' > "$1.clean"; }
part() { sed -n "/^==$2==\$/,/^==$3==\$/p" "$1.clean"; }

for M in $SIZES; do
    echo "== 2. new kernel, -m $M =="
    rc=$(run_case "n$M" "$NEW" "$M")
    F="$D/n$M.txt"; clean "$F"
    tot=$(sed -n 's/^mmap: .*, \([0-9]*\) KiB usable.*/\1/p' "$F.clean" | head -1)
    frm=$(sed -n 's/^frames: \([0-9]*\) covered.*/\1/p' "$F.clean" | head -1)
    [ -n "${MEMSIZE_KEEP:-}" ] && cp "$F.clean" "$MEMSIZE_KEEP/n$M.txt"
    want=$(( M * 1024 ))
    if [ -n "$tot" ] && [ "$tot" -le "$want" ] && [ "$tot" -ge $(( want * 9 / 10 )) ]; then ok "MemTotal $tot kB within 90-100% of $want kB"; else bad "MemTotal '$tot' vs $want kB"; fi
    if [ -n "$frm" ] && [ $(( frm * 4 )) -ge $(( want * 9 / 10 )) ]; then ok "frames cover the RAM: $frm"; else bad "frames '$frm' do not cover $M MiB"; fi
    nproc=1; [ "$M" -ge 8192 ] && nproc=2
    is "touched $(touch_for "$M") MiB x $nproc process(es)" "$(part "$F" TOUCH END | grep -ac '^hifr: end$')" "$nproc"
    is "read into a user page lands right" "$(part "$F" TOUCH END | grep -ac '^hifr: read ok$')" "$nproc"
    hasnot "$F.clean" "EXCEPTION" "no kernel page fault"
    is "no user fault" "$(part "$F" TOUCH END | grep -ac 'process killed')" "0"
done

echo "== 3. counter-proof: kernel with the 1 GiB confinement =="
if [ -n "$OLD" ]; then
    M=4096
    rc=$(run_case old "$OLD" "$M")
    F="$D/old.txt"; clean "$F"
    is "old kernel: touching $(touch_for "$M") MiB does not complete" "$(part "$F" TOUCH END | grep -ac '^hifr: end$')" "0"
else
    echo "  skip  no old kernel given"
fi

echo "memsize: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
