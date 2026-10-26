#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/xfer/run.sh -- the transfer service (clipboard, primary selection, drag payload): one service, typed lazy items.
#
#   bash tools/xfer/run.sh [workdir]
#
# 1. console: tools/xfer/guest.sh runs inside the guest through /bin/xclip; tools/xfer/check.py judges the serial output
#    (round trips 100 B .. 2 MiB with FNV sums, lazy handover counted by offers/fills, mime negotiation, custom mime types,
#    primary vs clipboard, ring of 20, file lists, drag slot next to the notification ring, no segment leak)
# 2. COUNTER-PROBES: three mutated copies of the tree must turn exactly the checks red that they should
#    (no segment adoption, no lazy handover, no release of evicted segments)
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
if [ -n "${1:-}" ]; then
    OUT=$1
else
    OUT=$(mktemp -d)
    trap 'rm -rf "$OUT"' EXIT
fi
mkdir -p "$OUT"
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "XFER: skipped, no qemu"; exit 0; }
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

PROGS="sh echo ls cat sleep xclip"

boot_tree() { # tree out
    ( cd "$1" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
      ALLTAGBUILD="$2.build" bash tools/alltag/build.sh "$2" mager=yes shot=no progs="$PROGS" \
        xfile="/xfer.sh=$ROOT/tools/xfer/guest.sh" script="sh /xfer.sh" ) > "$2.log" 2>&1
}

expect() { # serial check-name state
    local line
    line=$(python3 "$ROOT/tools/xfer/check.py" "$1" | grep -a "^CHECK $2 " | head -1)
    case "$3:$line" in
        ok:*" ok "*) ok "$2" ;;
        fail:*" fail "*) ok "counter-probe: $2 turns red" ;;
        *) bad "$2 -- expected $3, got: ${line:-missing}" ;;
    esac
}

echo "== 1. the service, end to end in the guest =="
boot_tree "$ROOT" "$OUT/main" || { bad "build/run failed"; tail -n 15 "$OUT/main.log"; }
S="$OUT/main/serial.txt"
[ -s "$S" ] && grep -aq "kernel: done" "$S" && ok "guest script ran to the end" || bad "guest script did not finish"
python3 "$ROOT/tools/xfer/check.py" "$S" > "$OUT/main.checks" 2>&1
while read -r _ name state note; do
    if [ "$state" = ok ]; then ok "$name"; else bad "$name -- $note"; fi
done < "$OUT/main.checks"
[ "$(wc -l < "$OUT/main.checks")" -ge 30 ] && ok "all check groups reported" || bad "check groups missing"

echo
echo "== 2. COUNTER-PROBES: mutated trees =="
mutant() { # name file sed-expression expected-red-checks...
    local name=$1 file=$2 expr=$3
    shift 3
    local T="$OUT/mut-$name"
    mkdir -p "$T"
    tar -C "$ROOT" --exclude=.git -cf - . | tar -C "$T" -xf -
    sed -i "$expr" "$T/$file"
    if cmp -s "$T/$file" "$ROOT/$file"; then bad "mutant $name: the sed expression changed nothing"; rm -rf "$T"; return; fi
    ( cd "$T" && ALLTAGBUILD="$OUT/mut-$name.build" bash tools/alltag/build.sh "$OUT/mut-$name-run" mager=yes shot=no progs="$PROGS" \
        xfile="/xfer.sh=$ROOT/tools/xfer/guest.sh" script="sh /xfer.sh" ) > "$OUT/mut-$name.log" 2>&1
    local MS="$OUT/mut-$name-run/serial.txt"
    [ -s "$MS" ] && ok "mutant $name booted" || { bad "mutant $name did not boot"; rm -rf "$T"; return; }
    local c
    for c in "$@"; do expect "$MS" "$c" fail; done
    rm -rf "$T" "$OUT/mut-$name.build"
}
mutant noadopt kernel/bus/bus.fi 's/seg_set(state, id, G_OWNER, ADOPT_PID)/seg_set(state, id, G_OWNER, seg_at(state, id, G_OWNER))/' \
    roundtrip_1048576 roundtrip_2097152
mutant eagerlazy kernel/bus/slots.fi 's/if (bus.item_get(a, bus.I_PRIO) & bit) == 0 {/if false {/' \
    lazy_fill_on_paste lazy_data_exact
mutant norelease kernel/bus/slots.fi 's/        bus.seg_release(state, seg1 - 1)/        let _z: u64 = seg1/' \
    eviction_frees_segments no_segment_leak

echo
echo "XFER: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
