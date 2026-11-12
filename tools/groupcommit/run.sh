#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
. tools/lib/firnenv.sh
ULD=kernel/user/user.ld
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0
fail=0
ok() { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
KERNEL=${GC_KERNEL:-}
if [ -z "$KERNEL" ]; then
    bash tools/build-kernel.sh "$TMPD/k.mb" --stufe 1 > "$TMPD/build.txt" 2>&1 || { echo "GROUPCOMMIT: kernel build failed"; exit 1; }
    KERNEL=$TMPD/k.mb
fi
as --64 -o "$TMPD/crt.o" kernel/user/crt.s || exit 1
PROGS="sh echo ls touch sync sleep"
SPEC="/bin/ /tmp/ /dev/ /proc/"
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/e$p" 2>&1 || { bad "$p does not compile"; continue; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null
    strip --strip-all "$TMPD/$p.elf" 2>/dev/null
    SPEC="$SPEC /bin/$p=$TMPD/$p.elf"
done
bash tools/mkfsfi/mkfs.sh build "$TMPD/base.img" 65536 --v3 --inodes=512 --journal --time=1780000000 $SPEC > /dev/null 2>&1 || { echo "GROUPCOMMIT: mkfs failed"; exit 1; }

present() {
    bash tools/mkfsfi/mkfs.sh list "$1" 2>/dev/null | grep -a -c "tmp/a"
}

scenario() {
    local name=$1 words=$2 script=$3 kill_after=$4
    local img=$TMPD/$name.img serial=$TMPD/$name.txt
    cp "$TMPD/base.img" "$img"
    timeout 180 qemu-system-x86_64 -accel tcg -kernel "$KERNEL" -m 512 -append "osum vfs nokbd $words script=$script" \
        -serial "file:$serial" -display none -no-reboot -drive "file=$img,format=raw,if=ide,index=0,cache=directsync" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
    local pid=$!
    if [ "$kill_after" != none ]; then
        for _ in $(seq 1 1200); do
            tr -d '\r' < "$serial" 2>/dev/null | grep -qa '^MARK' && break
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.05
        done
        sleep "$kill_after"
        kill -9 "$pid" 2>/dev/null
    fi
    wait "$pid" 2>/dev/null
    present "$img"
}

echo "== barriers =="
[ "$(scenario sync "" "touch /tmp/a;sync;echo MARK;sleep 30;exit" 0.3)" = 1 ] && ok "sync(2) persists the group before kill -9" || bad "file lost after sync + kill -9"
[ "$(scenario exit "" "touch /tmp/a;exit" none)" = 1 ] && ok "script end (shutdown path) persists the group" || bad "file lost after graceful shutdown"
[ "$(scenario idle "" "touch /tmp/a;echo MARK;sleep 30;exit" 3)" = 1 ] && ok "idle flush persists the group within 3 s" || bad "file lost after 3 s idle + kill -9"
[ "$(scenario nogroup nogroup "touch /tmp/a;echo MARK;sleep 30;exit" 0.1)" = 1 ] && ok "counter-proof nogroup: per-op commit survives kill -9 right away" || bad "nogroup lost the file"
echo "== window (informational) =="
echo "  INFO  kill -9 0.1 s after the op, group commit: file present = $(scenario window "" "touch /tmp/a;echo MARK;sleep 30;exit" 0.1)"
echo "GROUPCOMMIT: $pass passed, $fail failed"
[ "$fail" = 0 ]
