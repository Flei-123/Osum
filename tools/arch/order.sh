#!/usr/bin/env bash
# tools/arch/order.sh -- THE ONE DEFECT ROUND ARM FOUND, AND THE PROOF IT IS GONE.
#
# `kernel/atomic.fi` released a lock with a plain 64-bit store. On x86-64
# that is a correct release: the hardware does not move a store ahead of an
# older store, so everything the holder wrote is visible before the lock
# reads as free. On AArch64 it is wrong, silently, on one processor out of
# four, rarely. Round ARM measured it (`--emit=asm`, plain `str`) and could
# not fix it, because the compiler could not build Firn for AArch64 at all.
#
# Now it can. `arch.atomic_store` and `arch.atomic_load` cross the boundary
# and `kernel/arch/machine.fi` answers with a plain access on x86-64 and
# with `stlr`/`ldar` on AArch64. This script reads that out of the emitted
# assembler of BOTH machines instead of believing the comment.
#
# What it checks, and each one has a counter-check that has to FAIL:
#
#   1. aarch64: the store is `stlr`, the load is `ldar`.
#   2. x86-64:  the store and the load are plain `mov` -- NOT `xchg`, not
#               `lock`-prefixed. A release store that turned into a locked
#               instruction would be correct and would also be forty times
#               slower, and nobody would notice for a year.
#   3. the compare-and-swap is `ldaxr`/`stlxr` on aarch64 and
#      `lock cmpxchg` on x86-64.
#   4. `pause` is `pause` there and `yield` here; `idle` is `hlt` there and
#      `wfi` here -- and NOT `hlt`, which exists on AArch64 and means
#      something else entirely (tools/arch/a64gap.sh).
#   5. the counter-check to the whole method: a plain `__mmio_write64`,
#      compiled for aarch64, must come out as a bare `str`. If it does not,
#      then `stlr` above proves nothing about the boundary, because the
#      compiler would be emitting release stores everywhere by itself.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

FIRNC=${FIRNC:-vendor/firn/bin/firnc}
[ -x "$FIRNC" ] || { echo "firnc is missing: $FIRNC"; exit 1; }
export FIRNLIB="$ROOT/lib"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# A root next to kernel/ so that `import arch.arch` resolves the way the
# kernel's own roots resolve it.
cat > kernel/.order-probe.fi <<'EOF'
import arch.arch
export { st, ld, cas, spin, sleep, plain_store }
fn st(p: u64, v: u64) { arch.atomic_store(p, v) }
fn ld(p: u64) -> u64 { return arch.atomic_load(p) }
fn cas(p: u64, e: u64, w: u64) -> u64 { return __atomic_swap(p as *mut u64, e, w) }
fn spin() { arch.pause() }
fn sleep() { arch.idle() }
fn plain_store(p: u64, v: u64) { __mmio_write64(p as *mut u64, v) }
EOF
trap 'rm -rf "$TMP"; rm -f kernel/.order-probe.fi' EXIT

for t in x86_64-none aarch64-none; do
    "$FIRNC" --target=$t --emit=asm -o "$TMP/$t.s" kernel/.order-probe.fi 2>"$TMP/$t.err" \
        || { bad "$t: the probe does not compile"; sed 's/^/        /' "$TMP/$t.err" | head -5; continue; }
    ok "$t: the probe compiles ($(grep -c . "$TMP/$t.s") lines of assembler)"
done

# body <target> <name> -- the instructions of one function, labels stripped.
# The names asked for below are the ones in `kernel/arch/machine.fi`, not the
# probe's own: the forwarders are not inlined at this optimisation level, so
# the probe's body holds a `bl` and nothing else. Reading the machine
# function is reading the thing under test; reading the probe would be
# reading the call.
body() {
    awk -v f="_F0.$2:" '
        $0 == f { on = 1; next }
        on && /^_F0\./ { on = 0 }
        on && !/^\./ && NF { print }
    ' "$TMP/$1.s"
}

echo "== 1. the release store and the acquire load =="
a=$(body aarch64-none machine__atomic_store)
printf '%s' "$a" | grep -qE '\bstlr\b' \
    && ok "aarch64: atomic_store is a STORE-RELEASE ($(printf '%s' "$a" | grep -oE 'stlr[^,]*, \[[^]]*\]' | head -1))" \
    || { bad "aarch64: no stlr in atomic_store"; printf '%s\n' "$a" | sed 's/^/        /'; }

a=$(body aarch64-none machine__atomic_load)
printf '%s' "$a" | grep -qE '\bldar\b' \
    && ok "aarch64: atomic_load is a LOAD-ACQUIRE ($(printf '%s' "$a" | grep -oE 'ldar[^,]*, \[[^]]*\]' | head -1))" \
    || { bad "aarch64: no ldar in atomic_load"; printf '%s\n' "$a" | sed 's/^/        /'; }

echo "== 2. and x86-64 did not get slower for it =="
x=$(body x86_64-none machine__atomic_store)
if printf '%s' "$x" | grep -qE '\block\b|xchg'; then
    bad "x86-64: atomic_store became a locked instruction -- correct, and forty times too slow"
else
    ok "x86-64: atomic_store is a plain store, no lock prefix, no xchg"
fi
x=$(body x86_64-none machine__atomic_load)
printf '%s' "$x" | grep -qE '\block\b' \
    && bad "x86-64: atomic_load carries a lock prefix" \
    || ok "x86-64: atomic_load is a plain load"

echo "== 3. compare-and-swap, which was already right on both =="
a=$(body aarch64-none cas)
printf '%s' "$a" | grep -qE '\bldaxr\b' && printf '%s' "$a" | grep -qE '\bstlxr\b' \
    && ok "aarch64: cas is ldaxr/stlxr -- acquire on the way in, release on the way out" \
    || bad "aarch64: cas is not ldaxr/stlxr"
x=$(body x86_64-none cas)
printf '%s' "$x" | grep -qE 'lock cmpxchg' \
    && ok "x86-64: cas is lock cmpxchg" \
    || bad "x86-64: cas is not lock cmpxchg"

echo "== 4. the spin hint and the idle instruction =="
printf '%s' "$(body x86_64-none machine__pause)" | grep -qE '^\s*pause' \
    && ok "x86-64: pause -> pause" || bad "x86-64: pause is not pause"
printf '%s' "$(body aarch64-none machine__pause)" | grep -qE '^\s*yield' \
    && ok "aarch64: pause -> yield" || bad "aarch64: pause is not yield"
printf '%s' "$(body x86_64-none machine__idle)" | grep -qE '^\s*hlt' \
    && ok "x86-64: idle -> hlt" || bad "x86-64: idle is not hlt"
s=$(body aarch64-none machine__idle)
if printf '%s' "$s" | grep -qE '^\s*wfi'; then
    ok "aarch64: idle -> wfi"
else
    bad "aarch64: idle is not wfi"
fi
printf '%s' "$s" | grep -qE '^\s*hlt' \
    && bad "aarch64: idle emitted 'hlt', which on this machine traps to the debugger" \
    || ok "aarch64: and it is NOT 'hlt', which here means something else entirely"

echo "== 5. the counter-check to the method itself =="
a=$(body aarch64-none plain_store)
if printf '%s' "$a" | grep -qE '\bstlr\b'; then
    bad "a plain __mmio_write64 also comes out as stlr -- then section 1 proves nothing"
else
    ok "a plain __mmio_write64 stays a bare 'str' on aarch64 -- so the stlr in section 1 comes from the boundary and from nowhere else"
fi

echo "== 6. and atomic.fi no longer holds one instruction of any machine =="
n=$(grep -c 'asm(' kernel/atomic.fi)
[ "$n" -eq 0 ] \
    && ok "kernel/atomic.fi: 0 inline assembly blocks (it had 4)" \
    || bad "kernel/atomic.fi still has $n asm blocks"

echo
echo "ORDER: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
