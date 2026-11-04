#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/tmpdir.sh
D=$(mktemp -d)
osum_tmp_guard "${1:-}" "$D"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
pass=0
fail=0
ok() { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

build_run() {
    local lib=$1 out=$2 src=${3:-tools/libc/suite.fi} limit=${4:-120}
    FIRNLIB=$lib "$FIRNC" "$src" -o "$out" > "$out.log" 2>&1 || return 2
    ( timeout "$limit" "$out" ) > /dev/null 2>&1
}

echo "== 1. host suite over the pure libc modules =="
build_run "$PWD/lib" "$D/suite"; rc=$?
[ $rc -eq 0 ] && ok "octets, numeric, hexdigit, pathname, textsearch, locks agree with the reference values" || bad "suite rc=$rc"

echo "== 2. counter-proofs: a broken module must fail the suite =="
n=0
for edit in \
    "numeric.fi|s/return imin(imax(v, lo), hi)/return imax(imin(v, hi), lo) + 1/" \
    "octets.fi|s/return ld8(p, i) | (ld8(p, i + 1) << 8)/return ld8(p, i)/" \
    "hexdigit.fi|s/return v + 87/return v + 88/" \
    "pathname.fi|s/return at - 1/return at/" \
    "textsearch.fi|s/return text.equal(p + lp - ls, suffix)/return true/"; do
    mod=${edit%%|*}
    expr=${edit#*|}
    n=$((n+1))
    cp -r lib "$D/lib$n"
    sed -i "$expr" "$D/lib$n/libc/$mod"
    if cmp -s "lib/libc/$mod" "$D/lib$n/libc/$mod"; then bad "patch for $mod did not apply"; continue; fi
    build_run "$D/lib$n" "$D/bad$n"; rc=$?
    [ $rc -eq 1 ] && ok "broken $mod is caught" || bad "broken $mod not caught (rc=$rc)"
done

echo "== 3. threads: clone stub, join, mutex exclusion, lost updates without it =="
build_run "$PWD/lib" "$D/thr" tools/libc/threads_suite.fi; rc=$?
[ $rc -eq 0 ] && ok "threads: exact sum under mutex, lost updates without, join result, dead-thread join, distinct ids, deep stack, 300 spawns, thread_exit, detach + reaper, keys with destructors and generations, condvar broadcast/ping-pong, mutex_try, futex timeouts, cond_timedwait, mutex_timedlock, semaphore (blocking, timed, wake latency, producer/consumer, exclusion), once, rwlock (sharing, exclusion, writer preference, timed, timeout wakes readers), barrier (rounds, serial thread, blocking), pthread shim, attributes, recursive and errorcheck mutexes, E_DEADLK, try-read with waiting writer, barrier destroy, deferred cancel with cleanup handlers, cancel in semaphore/rwlock/barrier waits, recursive mutex depth over cond_wait, cancel of the main thread (pending)" || bad "threads suite rc=$rc"
runs=0
for i in 1 2 3 4 5 6 7 8; do
    "$D/thr" > /dev/null 2>&1 || runs=$((runs+1))
done
[ $runs -eq 0 ] && ok "threads suite stable over 8 more runs" || bad "threads suite failed $runs of 8 repeat runs"

echo "== 4. threads counter-proofs =="
for edit in \
    "threads.fi|s/while tid != 0 {/while false {/" \
    "threads.fi|s/in(\"rdx\") ptid/in(\"rdx\") 0/" \
    "threads.fi|s/octets.st64(top, 8, base)/octets.st64(top, 8, base + 8)/" \
    "threads.fi|s/kcall.sys1(kcall.SYS_EXIT, 0)/kcall.sys0(kcall.SYS_GETTID)/" \
    "threads.fi|s/reap_head = handle/reap_head = 0/" \
    "threads.fi|s/if gen != 0 \&\& dtor != 0 \&\&/if false \&\&/" \
    "threads.fi|s/if octets.ld64(gen_addr(handle, slot), 0) != key >> 8 {/if false {/" \
    "locks.fi|s/^    futex_wait(cv, seq)\$/    load(cv)/" \
    "locks.fi|s/seen = cas(p, 0, 2)/seen = 0/" \
    "locks.fi|s/if timed_out(r) {/if false {/" \
    "locks.fi|s/ts\\[1\\] = span % NS_PER_SEC/ts[1] = 0/" \
    "locks.fi|s/ts\\[0\\] = span \\/ NS_PER_SEC/ts[0] = 0/" \
    "semaphore.fi|s/locks.futex_wake(p, 1)/locks.load(p)/" \
    "semaphore.fi|s/locks.cas(p, v, v - 1) == v/true/" \
    "semaphore.fi|s/locks.fetch_add(p, 0 -% WAITER_ONE)/locks.load(p)/" \
    "once.fi|s/if locks.cas(p, 0, STATE_RUNNING) == 0 {/if true {/" \
    "once.fi|s/locks.futex_wake(p, locks.WAKE_ALL)/locks.load(p)/" \
    "rwlock.fi|s/if ((v >> 32) \& WRITER_WAIT_MASK) != 0 {/if false {/" \
    "rwlock.fi|s/return (v \& LOW_MASK) != 0/return (v \& WRITER_BIT) != 0/" \
    "rwlock.fi|s/if (after \& LOW_MASK) == 0 \&\& (before >> 32) != 0 {/if false {/" \
    "rwlock.fi|s/if (v >> 48) != 0 {/if false {/;s/span > pcancel.SLICE_NS/false/" \
    "rwlock.fi|s/locks.fetch_add(p, 0 -% READER_WAIT_ONE)/locks.load(p)/" \
    "rwlock.fi|s/if locks.cas(p, v, v - 1) == v {/if true {/" \
    "barrier.fi|s/(v + 1) \& WORD_MASK/v + ARRIVAL_ONE/" \
    "barrier.fi|s/locks.futex_wake(p + OFF_GEN, locks.WAKE_ALL)/locks.load(p + OFF_GEN)/" \
    "barrier.fi|s/return SERIAL/return 0/" \
    "barrier.fi|s/if (v >> 32) + 1 >= locks.load(p + OFF_COUNT) {/if (v >> 32) + 1 > locks.load(p + OFF_COUNT) {/" \
    "pthread.fi|s/if r == barrier.SERIAL {/if false {/" \
    "pmutex.fi|s/if locks.load(m) == 0 {/if false {/" \
    "pthread.fi|s/if threads.is_detached(t) {/if false {/" \
    "pthread.fi|s/if threads.key_delete(key) != 0 {/if false {/" \
    "pthread.fi|s/    threads.thread_exit(retval)/    threads.yield_now()/" \
    "pthread.fi|s/return errno.E_DEADLK/return errno.E_INVAL/" \
    "pthread.fi|s/let handle: u64 = threads.spawn_sized(body, arg, stack)/let handle: u64 = threads.spawn_sized(body, arg, threads.STACK_MIN)/" \
    "pthread.fi|s/^    if detached {/    if false {/" \
    "pattr.fi|s/if bytes < threads.STACK_MIN || bytes > STACK_LIMIT {/if false {/" \
    "pattr.fi|s/if state != CREATE_JOINABLE \&\& state != CREATE_DETACHED {/if false {/" \
    "pmutex.fi|s/return errno.E_DEADLK/return 0/" \
    "pmutex.fi|s/locks.store(m + OFF_COUNT, depth + 1)/locks.load(m)/" \
    "pmutex.fi|s/if owner_of(m) != threads.self_id() {/if false {/" \
    "pmutex.fi|s/^        claim(m, threads.self_id())/        locks.load(m)/" \
    "pmutex.fi|s/if depth >= COUNT_MAX {/if depth >= 1 {/" \
    "rwlock.fi|s/if try_read_blocked(v) {/if read_blocked(v) {/" \
    "barrier.fi|s/^    locks.fetch_add(p + OFF_BUSY, 0 -% 1)/    locks.load(p + OFF_BUSY)/" \
    "barrier.fi|s/^    locks.store(p + OFF_COUNT, 0)\$/    locks.load(p + OFF_COUNT)/" \
    "barrier.fi|s/if locks.load(p + OFF_COUNT) == 0 {/if false {/" \
    "pcancel.fi|s/locks.store(b + OFF_PENDING, 1)/locks.load(b + OFF_PENDING)/" \
    "pcancel.fi|s/^    locks.futex_wake(b + OFF_PENDING, locks.WAKE_ALL)/    locks.load(b + OFF_PENDING)/" \
    "pcancel.fi|s/return locks.load(b + OFF_PENDING) != 0 \&\& locks.load(b + OFF_DISABLED) == 0/return locks.load(b + OFF_PENDING) != 0/" \
    "pcancel.fi|s/^    run_cleanups()\$/    cleanup_depth()/" \
    "pcancel.fi|s/if state > STATE_DISABLE {/if false {/" \
    "semaphore.fi|s/if canceled {/if false {/" \
    "rwlock.fi|s/if canceled {/if false {/" \
    "barrier.fi|s/if locks.cas(p + OFF_GEN, v, v - ARRIVAL_ONE) == v {/if true {/" \
    "barrier.fi|s/ \&\& withdraw(p, gen) {/ \&\& true {/" \
    "pcancel.fi|s/locks.futex_wake(waiting, locks.WAKE_ALL)/locks.load(waiting)/" \
    "pcancel.fi|s/^    if t != 0 \&\& threads.is_done(t) {\$/    if t == 0 || threads.is_done(t) {/" \
    "pmutex.fi|s/locks.store(m + OFF_COUNT, depth)\$/locks.store(m + OFF_COUNT, 1)/" \
    "pmutex.fi|s/octets.st64(depth_out, 0, locks.load(m + OFF_COUNT))/octets.st64(depth_out, 0, 1)/" \
    "pcond.fi|s/^    pcancel.testcancel()\$/    pcancel.pending()/"; do
    mod=${edit%%|*}
    expr=${edit#*|}
    n=$((n+1))
    cp -r lib "$D/lib$n"
    sed -i "$expr" "$D/lib$n/libc/$mod"
    if cmp -s "lib/libc/$mod" "$D/lib$n/libc/$mod"; then bad "patch for $mod did not apply"; continue; fi
    build_run "$D/lib$n" "$D/bad$n" tools/libc/threads_suite.fi 25; rc=$?
    { [ $rc -ne 0 ] && [ $rc -ne 2 ]; } && ok "broken threads patch $n in $mod is caught (rc=$rc)" || bad "broken threads patch $n in $mod not caught (rc=$rc)"
done

echo "== 5. thread_exit in the main thread ends the process (exit_group) =="
exit_probe() {
    local lib=$1 out=$2
    FIRNLIB=$lib "$FIRNC" tools/libc/exit_main.fi -o "$out" > "$out.log" 2>&1 || return 90
    timeout 30 "$out" > "$out.txt" 2>&1
}
exit_probe "$PWD/lib" "$D/exitmain"; rc=$?
if [ $rc -eq 7 ] && grep -q '^threxit dtor$' "$D/exitmain.txt" && ! grep -q '^threxit late$' "$D/exitmain.txt"; then ok "main-thread thread_exit: exit code 7, destructors ran, sibling thread killed"; else bad "main-thread thread_exit semantics wrong (rc=$rc)"; fi
for edit in \
    "threads.fi|s/kcall.sys1(kcall.SYS_EXIT_GROUP, result)/kcall.sys1(kcall.SYS_EXIT, result)/" \
    "threads.fi|/^        run_destructors(0)\$/d"; do
    mod=${edit%%|*}
    expr=${edit#*|}
    n=$((n+1))
    cp -r lib "$D/lib$n"
    sed -i "$expr" "$D/lib$n/libc/$mod"
    if cmp -s "lib/libc/$mod" "$D/lib$n/libc/$mod"; then bad "patch for $mod did not apply"; continue; fi
    exit_probe "$D/lib$n" "$D/exitbad$n"; rc=$?
    if [ $rc -ne 90 ] && { [ $rc -ne 7 ] || ! grep -q '^threxit dtor$' "$D/exitbad$n.txt" || grep -q '^threxit late$' "$D/exitbad$n.txt"; }; then ok "broken main-thread exit patch $n in $mod is caught (rc=$rc)"; else bad "broken main-thread exit patch $n in $mod not caught (rc=$rc)"; fi
done

echo "== 6. cancelling the main thread ends the process after cleanup handlers and destructors =="
cancel_probe() {
    local lib=$1 out=$2
    FIRNLIB=$lib "$FIRNC" tools/libc/cancel_main.fi -o "$out" > "$out.log" 2>&1 || return 90
    timeout 30 "$out" > "$out.txt" 2>&1
}
cancel_probe "$PWD/lib" "$D/cancelmain"; rc=$?
if [ $rc -eq 255 ] && grep -q '^thrcancel0 cleanup$' "$D/cancelmain.txt" && grep -q '^thrcancel0 dtor$' "$D/cancelmain.txt" && ! grep -q '^thrcancel0 \(alive\|slow\)$' "$D/cancelmain.txt" && ! grep -q '^thrcancel0 late$' "$D/cancelmain.txt"; then ok "cancel(0): blocked main thread leaves semaphore wait, cleanup and destructor ran, exit code 255, sibling killed"; else bad "main-thread cancel semantics wrong (rc=$rc)"; fi
for edit in \
    "pcancel.fi|s/^    if t != 0 \&\& threads.is_done(t) {\$/    if t == 0 || threads.is_done(t) {/" \
    "pcancel.fi|s/locks.futex_wake(waiting, locks.WAKE_ALL)/locks.load(waiting)/" \
    "semaphore.fi|s/if canceled {/if false {/"; do
    mod=${edit%%|*}
    expr=${edit#*|}
    n=$((n+1))
    cp -r lib "$D/lib$n"
    sed -i "$expr" "$D/lib$n/libc/$mod"
    if cmp -s "lib/libc/$mod" "$D/lib$n/libc/$mod"; then bad "patch for $mod did not apply"; continue; fi
    cancel_probe "$D/lib$n" "$D/cancelbad$n"; rc=$?
    if [ $rc -ne 90 ] && { [ $rc -ne 255 ] || grep -q '^thrcancel0 \(alive\|slow\)$' "$D/cancelbad$n.txt"; }; then ok "broken main-thread cancel patch $n in $mod is caught (rc=$rc)"; else bad "broken main-thread cancel patch $n in $mod not caught (rc=$rc)"; fi
done

echo "== $pass ok, $fail fail =="
[ $fail -eq 0 ]
