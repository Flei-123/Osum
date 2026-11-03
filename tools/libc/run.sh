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
    local lib=$1 out=$2 src=${3:-tools/libc/suite.fi}
    FIRNLIB=$lib "$FIRNC" "$src" -o "$out" > "$out.log" 2>&1 || return 2
    ( timeout 120 "$out" ) > /dev/null 2>&1
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
[ $rc -eq 0 ] && ok "threads: exact sum under mutex, lost updates without, join result, dead-thread join, distinct ids, deep stack, 300 spawns, thread_exit, detach + reaper, keys with destructors and generations, condvar broadcast/ping-pong, mutex_try" || bad "threads suite rc=$rc"
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
    "locks.fi|s/seen = cas(p, 0, 2)/seen = 0/"; do
    mod=${edit%%|*}
    expr=${edit#*|}
    n=$((n+1))
    cp -r lib "$D/lib$n"
    sed -i "$expr" "$D/lib$n/libc/$mod"
    if cmp -s "lib/libc/$mod" "$D/lib$n/libc/$mod"; then bad "patch for $mod did not apply"; continue; fi
    build_run "$D/lib$n" "$D/bad$n" tools/libc/threads_suite.fi; rc=$?
    { [ $rc -ne 0 ] && [ $rc -ne 2 ]; } && ok "broken threads patch $n in $mod is caught (rc=$rc)" || bad "broken threads patch $n in $mod not caught (rc=$rc)"
done

echo "== $pass ok, $fail fail =="
[ $fail -eq 0 ]
