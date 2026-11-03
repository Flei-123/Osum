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
mkdir -p "$TMPD/bin" "$TMPD/badbin" "$TMPD/notlsbin" "$TMPD/nocvbin"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then ok "programs build"; else sed 's/^/        /' "$TMPD/b.txt" | head -20; bad "programs do not build"; echo "LIBC-GUEST: $pass passed, $fail failed"; exit 1; fi
cp -r lib "$TMPD/badlib"
sed -i 's/while tid != 0 {/while false {/' "$TMPD/badlib/libc/threads.fi"
cp -r lib "$TMPD/notlslib"
sed -i 's/CLONE_THREAD | CLONE_SYSVSEM | CLONE_SETTLS |/CLONE_THREAD | CLONE_SYSVSEM |/' "$TMPD/notlslib/libc/threads.fi"
cp -r lib "$TMPD/nocvlib"
sed -i 's/^    futex_wait(cv, seq)$/    load(cv)/' "$TMPD/nocvlib/libc/locks.fi"
if cmp -s lib/libc/locks.fi "$TMPD/nocvlib/libc/locks.fi"; then bad "counter-proof no-condvar-futex mutation did not apply"; fi
if FIRNLIB="$TMPD/nocvlib" bash tools/sync/build.sh "$TMPD/nocvbin" 0 thrprobe > "$TMPD/nc.txt" 2>&1; then ok "counter-proof no-condvar-futex program builds"; else bad "counter-proof no-condvar-futex program does not build"; fi
if cmp -s lib/libc/threads.fi "$TMPD/notlslib/libc/threads.fi"; then bad "counter-proof no-TLS mutation did not apply"; fi
if FIRNLIB="$TMPD/notlslib" bash tools/sync/build.sh "$TMPD/notlsbin" 0 thrprobe > "$TMPD/nb.txt" 2>&1; then ok "counter-proof no-TLS program builds"; else bad "counter-proof no-TLS program does not build"; fi
if FIRNLIB="$TMPD/badlib" bash tools/sync/build.sh "$TMPD/badbin" 0 thrprobe > "$TMPD/bb.txt" 2>&1; then ok "counter-proof program builds"; else bad "counter-proof program does not build"; fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then ok "kernel builds"; else tail -8 "$TMPD/k.txt" | sed 's/^/        /'; bad "kernel does not build"; echo "LIBC-GUEST: $pass passed, $fail failed"; exit 1; fi

{
    echo "echo ==GOOD=="
    echo "thrprobe"
    echo "echo ==BAD=="
    echo "thrprobe_bad"
    echo "echo ==NOTLS=="
    echo "thrprobe_notls"
    echo "echo ==NOCV=="
    echo "thrprobe_nocv"
    echo "echo ==END=="
} > "$TMPD/s.sh"
{
    echo "echo ==LAT=="
    echo "thrprobe"
    echo "echo ==END=="
} > "$TMPD/s2.sh"
A=(build "$TMPD/d.img" 20000 /bin/ /t/ /tmp/ /proc/ /dev/ /etc/)
for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
[ -f "$TMPD/badbin/thrprobe.elf" ] && A+=("/bin/thrprobe_bad=$TMPD/badbin/thrprobe.elf")
[ -f "$TMPD/nocvbin/thrprobe.elf" ] && A+=("/bin/thrprobe_nocv=$TMPD/nocvbin/thrprobe.elf")
[ -f "$TMPD/notlsbin/thrprobe.elf" ] && A+=("/bin/thrprobe_notls=$TMPD/notlsbin/thrprobe.elf")
A+=("/t/s.sh=$TMPD/s.sh" "/t/s2.sh=$TMPD/s2.sh")
bash tools/mkfsfi/mkfs.sh "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 || { tail -3 "$TMPD/mkfs.txt"; bad "mkfs"; echo "LIBC-GUEST: $pass passed, $fail failed"; exit 1; }

timeout 600 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp "$CORES" \
    -kernel "$TMPD/k0.img" -m 512 \
    -append "osum vfs nokbd smpfrueh script=sh /t/s.sh;exit" \
    -serial "file:$TMPD/out.txt" -display none -no-reboot \
    -drive "file=$TMPD/d.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$TMPD/out.txt" > "$TMPD/out.klar" 2>/dev/null || true

cp "$TMPD/d.img" "$TMPD/d2.img"
timeout 600 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp "$CORES" \
    -kernel "$TMPD/k0.img" -m 512 \
    -append "osum vfs nokbd smpfrueh noctidwake script=sh /t/s2.sh;exit" \
    -serial "file:$TMPD/out2.txt" -display none -no-reboot \
    -drive "file=$TMPD/d2.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$TMPD/out2.txt" > "$TMPD/out2.klar" 2>/dev/null || true

good=$(sed -n '/==GOOD==/,/==BAD==/p' "$TMPD/out.klar")
badout=$(sed -n '/==BAD==/,/==NOTLS==/p' "$TMPD/out.klar")
notlsout=$(sed -n '/==NOTLS==/,/==NOCV==/p' "$TMPD/out.klar")
nocvout=$(sed -n '/==NOCV==/,/==END==/p' "$TMPD/out.klar")
latout=$(sed -n '/==LAT==/,/==END==/p' "$TMPD/out2.klar")
echo "$good" | grep -aq 'thrprobe failed=0' && echo "$good" | grep -aq 'thrprobe done' \
    && ok "guest: threads suite passed ($(echo "$good" | grep -a 'thrprobe passed=' | tr -d '\r'))" \
    || { echo "$good" | tail -8 | sed 's/^/        /'; bad "guest: threads suite failed or incomplete"; }
if echo "$badout" | grep -aq 'thrprobe failed=0'; then
    bad "guest: counter-proof (join not waiting) still passed"
else
    ok "guest: counter-proof (join not waiting) is caught"
fi
echo "$good" | grep -aq 'thrprobe latency_ticks' && ok "guest: join latency with futex wake ($(echo "$good" | grep -a 'latency_ticks' | tr -d '\r'))" || bad "guest: no latency line"
if echo "$notlsout" | grep -aq 'thrprobe failed=0'; then
    bad "guest: counter-proof (no CLONE_SETTLS) still passed"
else
    ok "guest: counter-proof (no CLONE_SETTLS) is caught"
fi
if echo "$nocvout" | grep -aq 'thrprobe failed=0'; then
    bad "guest: counter-proof (condvar without futex wait) still passed"
else
    echo "$nocvout" | grep -aq 'thrprobe done' && ok "guest: counter-proof (condvar without futex wait) is caught" || bad "guest: counter-proof no-condvar run incomplete"
fi
if echo "$latout" | grep -aq 'thrprobe latency bad'; then
    ok "guest: counter-proof (kernel without clear-tid wake) is caught ($(echo "$latout" | grep -a 'latency_ticks' | tr -d '\r'))"
else
    bad "guest: counter-proof (kernel without clear-tid wake) not caught"
fi
echo; echo "LIBC-GUEST: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
