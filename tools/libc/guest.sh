#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
. tools/lib/tmpdir.sh
CORES=${1:-4}
TMPD=$(mktemp -d)
osum_tmp_guard "" "$TMPD"
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
PROGS="sh echo thrprobe"

echo "== build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$TMPD/bin" "$TMPD/badbin"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then ok "programs build"; else sed 's/^/        /' "$TMPD/b.txt" | head -20; bad "programs do not build"; echo "LIBC-GUEST: $pass passed, $fail failed"; exit 1; fi
cp -r lib "$TMPD/badlib"
sed -i 's/while tid != 0 {/while false {/' "$TMPD/badlib/libc/threads.fi"
if FIRNLIB="$TMPD/badlib" bash tools/sync/build.sh "$TMPD/badbin" 0 thrprobe > "$TMPD/bb.txt" 2>&1; then ok "counter-proof program builds"; else bad "counter-proof program does not build"; fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then ok "kernel builds"; else tail -8 "$TMPD/k.txt" | sed 's/^/        /'; bad "kernel does not build"; echo "LIBC-GUEST: $pass passed, $fail failed"; exit 1; fi

{
    echo "echo ==GOOD=="
    echo "thrprobe"
    echo "echo ==BAD=="
    echo "thrprobe_bad"
    echo "echo ==END=="
} > "$TMPD/s.sh"
A=(build "$TMPD/d.img" 20000 /bin/ /t/ /tmp/ /proc/ /dev/ /etc/)
for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
[ -f "$TMPD/badbin/thrprobe.elf" ] && A+=("/bin/thrprobe_bad=$TMPD/badbin/thrprobe.elf")
A+=("/t/s.sh=$TMPD/s.sh")
bash tools/mkfsfi/mkfs.sh "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 || { tail -3 "$TMPD/mkfs.txt"; bad "mkfs"; echo "LIBC-GUEST: $pass passed, $fail failed"; exit 1; }

timeout 600 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp "$CORES" \
    -kernel "$TMPD/k0.img" -m 512 \
    -append "osum vfs nokbd smpfrueh script=sh /t/s.sh;exit" \
    -serial "file:$TMPD/out.txt" -display none -no-reboot \
    -drive "file=$TMPD/d.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$TMPD/out.txt" > "$TMPD/out.klar" 2>/dev/null || true

good=$(sed -n '/==GOOD==/,/==BAD==/p' "$TMPD/out.klar")
badout=$(sed -n '/==BAD==/,/==END==/p' "$TMPD/out.klar")
echo "$good" | grep -aq 'thrprobe failed=0' && echo "$good" | grep -aq 'thrprobe done' \
    && ok "guest: threads suite passed ($(echo "$good" | grep -a 'thrprobe passed=' | tr -d '\r'))" \
    || { echo "$good" | tail -8 | sed 's/^/        /'; bad "guest: threads suite failed or incomplete"; }
if echo "$badout" | grep -aq 'thrprobe failed=0'; then
    bad "guest: counter-proof (join not waiting) still passed"
else
    ok "guest: counter-proof (join not waiting) is caught"
fi
echo; echo "LIBC-GUEST: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
