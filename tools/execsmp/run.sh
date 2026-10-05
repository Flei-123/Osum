#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/execsmp/run.sh -- r360: THE ARGUMENTS OF exec/execve ARE PER CORE.
#
#   bash tools/execsmp/run.sh [<rounds>] [<workers>] [<cores>]
#
# Before: `sys.do_execve` (and `do_exec`, the open-with path, the desktop
# spawner) copied the argument list into ONE page for the whole machine
# (kstate.EARG_OFF) BEFORE the loader lock was taken. Two cores in
# `execve` at once filled it together; one program started with the
# other's arguments.
# After: one page per core (kstate.EARGK_OFF), valid because a system call
# runs with the interrupt flag down.
#
# Measures (guest: `execsmp`, kernel/user/execsmp.fi; every child checks its
# own argv: id, letter, length):
#   fix      execve variant and exec (spawn) variant, <rounds> x <workers>
#            children each: bad must be 0 and `execsmp: done` must show
#   counter  the same with the kernel word `noeargk` (one shared page):
#            at least one of the two variants must show bad > 0, otherwise
#            the test measures nothing
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
ROUNDS=${1:-4}
WORKERS=${2:-4}
CORES=${3:-4}
BATCH=${4:-2}
BOOTS=${5:-3}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
TMPD=${EXECSMP_DIR:-$(mktemp -d)}; mkdir -p "$TMPD"
[ -n "${EXECSMP_KEEP:-}" ] || trap 'rm -rf "$TMPD"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
PROGS="sh echo execsmp"

echo "== build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$TMPD/bin"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "programs build"
else
    sed 's/^/        /' "$TMPD/b.txt" | head -20; bad "programs do not build"
    echo "EXECSMP: $pass passed, $fail failed"; exit 1
fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then
    ok "kernel builds"
else
    tail -8 "$TMPD/k.txt" | sed 's/^/        /'; bad "kernel does not build"
    echo "EXECSMP: $pass passed, $fail failed"; exit 1
fi

{
    echo "echo ==EXEC=="
    for _ in $(seq 1 "$BATCH"); do echo "execsmp run exec $ROUNDS $WORKERS"; done
    echo "echo ==END=="
} > "$TMPD/s.sh"
A=(build "$TMPD/d.img" 20000 /bin/ /t/ /tmp/ /proc/ /dev/ /etc/)
for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
A+=("/t/s.sh=$TMPD/s.sh")
python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 || { tail -3 "$TMPD/mkfs.txt"; bad "mkfs"; exit 1; }

run() { # <name> <extra kernel words>
    local nm=$1 extra=$2
    cp -f "$TMPD/d.img" "$TMPD/$nm.img"
    timeout 600 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp "$CORES" \
        -kernel "$TMPD/k0.img" -m 512 \
        -append "osum vfs nokbd $extra script=sh /t/s.sh;exit" \
        -serial "file:$TMPD/$nm.txt" -display none -no-reboot \
        -drive "file=$TMPD/$nm.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$TMPD/$nm.txt" > "$TMPD/$nm.klar" 2>/dev/null || true
    rm -f "$TMPD/$nm.img"
}
# the number after "bad=" of the section between two markers
# total of "bad=" over the runs of the guest (? when a run is missing)
badof() { grep -a 'execsmp: children=' "$1" | awk -v n="$BATCH" '{s+=$NF; c++} END{if (c==n) print s; else print "?"}'; }

echo "== fix: $BOOTS boots x $BATCH runs x ($ROUNDS rounds x $WORKERS children), $CORES cores =="
fixbad=0; fixmiss=0
for n in $(seq 1 "$BOOTS"); do
    run "fix$n" "smpfrueh"
    b=$(badof "$TMPD/fix$n.klar")
    echo "        boot $n: bad=$b"
    if [ "$b" = "?" ]; then fixmiss=$((fixmiss+1)); else fixbad=$((fixbad+b)); fi
done
[ "$fixmiss" -eq 0 ] && [ "$fixbad" -eq 0 ] \
    && ok "execve: every child got its own arguments ($((BOOTS*BATCH*ROUNDS*WORKERS)) children, $CORES cores)" \
    || bad "execve: $fixbad wrong argument lists, $fixmiss incomplete boots"

echo "== counter-proof: noeargk (one shared page), $BOOTS boots =="
cntbad=0
for n in $(seq 1 "$BOOTS"); do
    run "cnt$n" "smpfrueh noeargk"
    b=$(badof "$TMPD/cnt$n.klar")
    echo "        boot $n: bad=$b"
    [ "$b" != "?" ] && cntbad=$((cntbad+b))
done
[ "$cntbad" -gt 0 ] \
    && ok "without the per-core page the arguments get mixed ($cntbad wrong lists)" \
    || bad "without the per-core page nothing went wrong -- the test measures nothing"

echo; echo "EXECSMP: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
