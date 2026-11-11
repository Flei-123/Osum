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
PROGS="sh echo sleep thrprobe threxit thrwake thrcancel0"

echo "== build =="
. tools/lib/firnenv.sh
mkdir -p "$TMPD/norwbin" "$TMPD/nobarbin" "$TMPD/bin" "$TMPD/badbin" "$TMPD/notlsbin" "$TMPD/nocvbin" "$TMPD/nosemlib_bin" "$TMPD/nocancelbin" "$TMPD/noexitbin" "$TMPD/nocmbin" "$TMPD/nonudgebin"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then ok "programs build"; else sed 's/^/        /' "$TMPD/b.txt" | head -20; bad "programs do not build"; echo "LIBC-GUEST: $pass passed, $fail failed"; exit 1; fi
cp -r lib "$TMPD/badlib"
sed -i 's/while tid != 0 {/while false {/' "$TMPD/badlib/libc/threads.fi"
cp -r lib "$TMPD/notlslib"
sed -i 's/CLONE_THREAD | CLONE_SYSVSEM | CLONE_SETTLS |/CLONE_THREAD | CLONE_SYSVSEM |/' "$TMPD/notlslib/libc/threads.fi"
cp -r lib "$TMPD/nocvlib"
sed -i 's/^    futex_wait(cv, seq)$/    load(cv)/' "$TMPD/nocvlib/libc/locks.fi"
cp -r lib "$TMPD/nosemlib"
sed -i 's/locks.futex_wake(p, 1)/locks.load(p)/' "$TMPD/nosemlib/libc/semaphore.fi"
cp -r lib "$TMPD/nocancellib"
sed -i 's/^    locks.futex_wake(b + OFF_PENDING, locks.WAKE_ALL)/    locks.load(b + OFF_PENDING)/' "$TMPD/nocancellib/libc/pcancel.fi"
cp -r lib "$TMPD/noexitlib"
sed -i 's/kcall.sys1(kcall.SYS_EXIT_GROUP, result)/kcall.sys1(kcall.SYS_EXIT, result)/' "$TMPD/noexitlib/libc/threads.fi"
cp -r lib "$TMPD/norwlib"
sed -i 's/if (after \& LOW_MASK) == 0 \&\& (before >> 32) != 0 {/if false {/' "$TMPD/norwlib/libc/rwlock.fi"
cp -r lib "$TMPD/nobarlib"
sed -i 's/locks.futex_wake(p + OFF_GEN, locks.WAKE_ALL)/locks.load(p + OFF_GEN)/' "$TMPD/nobarlib/libc/barrier.fi"
if cmp -s lib/libc/rwlock.fi "$TMPD/norwlib/libc/rwlock.fi"; then bad "counter-proof no-rwlock-wake mutation did not apply"; fi
if cmp -s lib/libc/barrier.fi "$TMPD/nobarlib/libc/barrier.fi"; then bad "counter-proof no-barrier-wake mutation did not apply"; fi
if FIRNLIB="$TMPD/norwlib" bash tools/sync/build.sh "$TMPD/norwbin" 0 thrwake > "$TMPD/nr.txt" 2>&1; then ok "counter-proof no-rwlock-wake program builds"; else bad "counter-proof no-rwlock-wake program does not build"; fi
if FIRNLIB="$TMPD/nobarlib" bash tools/sync/build.sh "$TMPD/nobarbin" 0 thrwake > "$TMPD/nbr.txt" 2>&1; then ok "counter-proof no-barrier-wake program builds"; else bad "counter-proof no-barrier-wake program does not build"; fi
if cmp -s lib/libc/semaphore.fi "$TMPD/nosemlib/libc/semaphore.fi"; then bad "counter-proof no-semaphore-wake mutation did not apply"; fi
if cmp -s lib/libc/threads.fi "$TMPD/noexitlib/libc/threads.fi"; then bad "counter-proof no-exit-group mutation did not apply"; fi
if cmp -s lib/libc/pcancel.fi "$TMPD/nocancellib/libc/pcancel.fi"; then bad "counter-proof no-cancel-wake mutation did not apply"; fi
if FIRNLIB="$TMPD/nocancellib" bash tools/sync/build.sh "$TMPD/nocancelbin" 0 thrprobe > "$TMPD/ncl.txt" 2>&1; then ok "counter-proof no-cancel-wake program builds"; else bad "counter-proof no-cancel-wake program does not build"; fi
if FIRNLIB="$TMPD/nosemlib" bash tools/sync/build.sh "$TMPD/nosemlib_bin" 0 thrprobe > "$TMPD/ns.txt" 2>&1; then ok "counter-proof no-semaphore-wake program builds"; else bad "counter-proof no-semaphore-wake program does not build"; fi
if FIRNLIB="$TMPD/noexitlib" bash tools/sync/build.sh "$TMPD/noexitbin" 0 threxit > "$TMPD/ne.txt" 2>&1; then ok "counter-proof no-exit-group program builds"; else bad "counter-proof no-exit-group program does not build"; fi
if cmp -s lib/libc/locks.fi "$TMPD/nocvlib/libc/locks.fi"; then bad "counter-proof no-condvar-futex mutation did not apply"; fi
if FIRNLIB="$TMPD/nocvlib" bash tools/sync/build.sh "$TMPD/nocvbin" 0 thrprobe > "$TMPD/nc.txt" 2>&1; then ok "counter-proof no-condvar-futex program builds"; else bad "counter-proof no-condvar-futex program does not build"; fi
if cmp -s lib/libc/threads.fi "$TMPD/notlslib/libc/threads.fi"; then bad "counter-proof no-TLS mutation did not apply"; fi
if FIRNLIB="$TMPD/notlslib" bash tools/sync/build.sh "$TMPD/notlsbin" 0 thrprobe > "$TMPD/nb.txt" 2>&1; then ok "counter-proof no-TLS program builds"; else bad "counter-proof no-TLS program does not build"; fi
if FIRNLIB="$TMPD/badlib" bash tools/sync/build.sh "$TMPD/badbin" 0 thrprobe > "$TMPD/bb.txt" 2>&1; then ok "counter-proof program builds"; else bad "counter-proof program does not build"; fi
cp -r lib "$TMPD/nocmlib"
sed -i 's/^    if t != 0 \&\& threads.is_done(t) {$/    if t == 0 || threads.is_done(t) {/' "$TMPD/nocmlib/libc/pcancel.fi"
cp -r lib "$TMPD/nonudgelib"
sed -i 's/locks.futex_wake(waiting, locks.WAKE_ALL)/locks.load(waiting)/' "$TMPD/nonudgelib/libc/pcancel.fi"
if cmp -s lib/libc/pcancel.fi "$TMPD/nocmlib/libc/pcancel.fi"; then bad "counter-proof no-main-cancel mutation did not apply"; fi
if cmp -s lib/libc/pcancel.fi "$TMPD/nonudgelib/libc/pcancel.fi"; then bad "counter-proof no-cancel-nudge mutation did not apply"; fi
if FIRNLIB="$TMPD/nocmlib" bash tools/sync/build.sh "$TMPD/nocmbin" 0 thrcancel0 > "$TMPD/ncm.txt" 2>&1; then ok "counter-proof no-main-cancel program builds"; else bad "counter-proof no-main-cancel program does not build"; fi
if FIRNLIB="$TMPD/nonudgelib" bash tools/sync/build.sh "$TMPD/nonudgebin" 0 thrcancel0 > "$TMPD/nnu.txt" 2>&1; then ok "counter-proof no-cancel-nudge program builds"; else bad "counter-proof no-cancel-nudge program does not build"; fi
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
    echo "echo ==NOSEM=="
    echo "thrprobe_nosem"
    echo "echo ==NOCANCEL=="
    echo "thrprobe_nocancel"
    echo "echo ==EXITGOOD=="
    echo "threxit"
    echo "sleep 3"
    echo "echo ==EXITBAD=="
    echo "threxit_bad"
    echo "sleep 3"
    echo "echo ==WAKEGOOD=="
    echo "thrwake"
    echo "echo ==WAKENORW=="
    echo "thrwake_norw"
    echo "echo ==WAKENOBAR=="
    echo "thrwake_nobar"
    echo "echo ==CANCEL0GOOD=="
    echo "thrcancel0"
    echo "sleep 3"
    echo "echo ==CANCEL0NOMAIN=="
    echo "thrcancel0_nomain"
    echo "sleep 3"
    echo "echo ==CANCEL0NONUDGE=="
    echo "thrcancel0_nonudge"
    echo "sleep 3"
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
[ -f "$TMPD/nosemlib_bin/thrprobe.elf" ] && A+=("/bin/thrprobe_nosem=$TMPD/nosemlib_bin/thrprobe.elf")
[ -f "$TMPD/nocancelbin/thrprobe.elf" ] && A+=("/bin/thrprobe_nocancel=$TMPD/nocancelbin/thrprobe.elf")
[ -f "$TMPD/noexitbin/threxit.elf" ] && A+=("/bin/threxit_bad=$TMPD/noexitbin/threxit.elf")
[ -f "$TMPD/norwbin/thrwake.elf" ] && A+=("/bin/thrwake_norw=$TMPD/norwbin/thrwake.elf")
[ -f "$TMPD/nobarbin/thrwake.elf" ] && A+=("/bin/thrwake_nobar=$TMPD/nobarbin/thrwake.elf")
[ -f "$TMPD/nocmbin/thrcancel0.elf" ] && A+=("/bin/thrcancel0_nomain=$TMPD/nocmbin/thrcancel0.elf")
[ -f "$TMPD/nonudgebin/thrcancel0.elf" ] && A+=("/bin/thrcancel0_nonudge=$TMPD/nonudgebin/thrcancel0.elf")
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
nocvout=$(sed -n '/==NOCV==/,/==NOSEM==/p' "$TMPD/out.klar")
nosemout=$(sed -n '/==NOSEM==/,/==NOCANCEL==/p' "$TMPD/out.klar")
nocancelout=$(sed -n '/==NOCANCEL==/,/==EXITGOOD==/p' "$TMPD/out.klar")
exitgood=$(sed -n '/==EXITGOOD==/,/==EXITBAD==/p' "$TMPD/out.klar")
exitbad=$(sed -n '/==EXITBAD==/,/==WAKEGOOD==/p' "$TMPD/out.klar")
wakegood=$(sed -n '/==WAKEGOOD==/,/==WAKENORW==/p' "$TMPD/out.klar")
wakenorw=$(sed -n '/==WAKENORW==/,/==WAKENOBAR==/p' "$TMPD/out.klar")
wakenobar=$(sed -n '/==WAKENOBAR==/,/==CANCEL0GOOD==/p' "$TMPD/out.klar")
cancel0good=$(sed -n '/==CANCEL0GOOD==/,/==CANCEL0NOMAIN==/p' "$TMPD/out.klar")
cancel0nomain=$(sed -n '/==CANCEL0NOMAIN==/,/==CANCEL0NONUDGE==/p' "$TMPD/out.klar")
cancel0nonudge=$(sed -n '/==CANCEL0NONUDGE==/,/==END==/p' "$TMPD/out.klar")
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
if echo "$nosemout" | grep -aq 'thrprobe failed=0'; then
    bad "guest: counter-proof (semaphore post without wake) still passed"
else
    echo "$nosemout" | grep -aq 'thrprobe done' && ok "guest: counter-proof (semaphore post without wake) is caught" || bad "guest: counter-proof no-semaphore-wake run incomplete"
fi
if echo "$nocancelout" | grep -aq 'thrprobe failed=0'; then
    bad "guest: counter-proof (cancel without wake) still passed"
else
    echo "$nocancelout" | grep -aq 'thrprobe done' && ok "guest: counter-proof (cancel without wake) is caught" || bad "guest: counter-proof no-cancel-wake run incomplete"
fi
if echo "$exitgood" | grep -aq 'threxit dtor' && ! echo "$exitgood" | grep -aq 'threxit late'; then
    ok "guest: main-thread thread_exit runs destructors and exit_group kills the sibling"
else
    echo "$exitgood" | tail -6 | sed 's/^/        /'; bad "guest: main-thread thread_exit semantics wrong"
fi
if echo "$exitbad" | grep -aq 'threxit late'; then
    ok "guest: counter-proof (plain exit in the main thread) is caught"
else
    bad "guest: counter-proof (plain exit in the main thread) not caught"
fi
if echo "$wakegood" | grep -aq 'thrwake failed=0' && echo "$wakegood" | grep -aq 'thrwake done'; then
    ok "guest: rwlock and barrier wake latency under 500 ms ($(echo "$wakegood" | grep -a 'thrwake passed=' | tr -d '\r'))"
else
    echo "$wakegood" | tail -6 | sed 's/^/        /'; bad "guest: rwlock/barrier wake probes failed or incomplete"
fi
if echo "$wakenorw" | grep -aq 'thrwake failed=0'; then
    bad "guest: counter-proof (rwlock unlock without wake) still passed"
else
    echo "$wakenorw" | grep -aq 'thrwake done' && ok "guest: counter-proof (rwlock unlock without wake) is caught" || bad "guest: counter-proof no-rwlock-wake run incomplete"
fi
if echo "$wakenobar" | grep -aq 'thrwake failed=0'; then
    bad "guest: counter-proof (barrier without wake) still passed"
else
    echo "$wakenobar" | grep -aq 'thrwake done' && ok "guest: counter-proof (barrier without wake) is caught" || bad "guest: counter-proof no-barrier-wake run incomplete"
fi
if echo "$cancel0good" | grep -aq 'thrcancel0 cleanup' && echo "$cancel0good" | grep -aq 'thrcancel0 dtor' && ! echo "$cancel0good" | grep -aq 'thrcancel0 \(alive\|slow\)' && ! echo "$cancel0good" | grep -aq 'thrcancel0 late'; then
    ok "guest: cancel(0) takes the blocked main thread out of its semaphore wait, runs cleanup and destructor, kills the sibling"
else
    echo "$cancel0good" | tail -6 | sed 's/^/        /'; bad "guest: main-thread cancel semantics wrong"
fi
if echo "$cancel0nomain" | grep -aq 'thrcancel0 \(alive\|late\|slow\)'; then
    ok "guest: counter-proof (cancel(0) ignored) is caught"
else
    bad "guest: counter-proof (cancel(0) ignored) not caught"
fi
if echo "$cancel0nonudge" | grep -aq 'thrcancel0 \(alive\|late\|slow\)'; then
    ok "guest: counter-proof (cancel without waking the blocked waiter) is caught"
else
    bad "guest: counter-proof (cancel without waking the blocked waiter) not caught"
fi
echo; echo "LIBC-GUEST: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
