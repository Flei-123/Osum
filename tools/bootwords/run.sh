#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
. tools/lib/summary.sh
. tools/lib/pidkill.sh
. tools/lib/tmpdir.sh

TMPD=$(mktemp -d)
osum_tmp_guard "" "$TMPD"
summary_begin BOOTWORDS
trap 'summary_guard; rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

LIMIT=${BOOTWORDS_LIMIT:-0}
JOBS=${BOOTWORDS_JOBS:-4}
BASE_WORDS="osum modedump nokbd noproc nofs noring3"

boot_bits() {
    local kernel=$1 name=$2 words=$3 log="$TMPD/$2.txt" pid i
    rm -f "$log"
    $QEMU_X86 -kernel "$kernel" -m 256 -append "$words" \
        -serial "file:$log" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    pid=$!
    for i in $(seq 1 300); do
        grep -aq '^boot: modes ' "$log" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2
    done
    osum_kill_tree "$pid"
    wait "$pid" 2>/dev/null
    python3 tools/bootwords/plan.py bits "$log"
}

has_bit() {
    local list=" $1 " bit=$2
    case $list in *" $bit "*) return 0;; esac
    return 1
}

check_group() {
    local tag=$1 base=$2 b=$3 bit_b=$4 specs=$5 got spec a bit_a kind
    got=$(cat "$TMPD/bits-$tag-$b" 2>/dev/null)
    if [ ! -s "$TMPD/bits-$tag-$b" ]; then
        bad "$tag: boot with '$b' printed no mode vector"
        return
    fi
    if has_bit "$got" "$bit_b"; then
        ok "$tag: '$b' alone sets its own mode (bit $bit_b)"
    else
        bad "$tag: '$b' alone does not set its own mode (bit $bit_b)"
    fi
    for spec in $specs; do
        IFS=, read -r a bit_a kind <<< "$spec"
        if has_bit "$base" "$bit_a"; then
            continue
        fi
        if [ "$kind" = find_lead ]; then
            if has_bit "$got" "$bit_a"; then
                ok "$tag: '$b' sets the family word '$a' (bit $bit_a, by design)"
            else
                bad "$tag: '$b' should set the family word '$a' (bit $bit_a)"
            fi
        elif has_bit "$got" "$bit_a"; then
            bad "$tag: '$b' alone switched on its neighbour '$a' (bit $bit_a)"
        else
            ok "$tag: '$b' alone leaves '$a' off (bit $bit_a)"
        fi
    done
}

run_pairs() {
    local kernel=$1 tag=$2 b bit_b specs base bad_before=$fail running=0 plan_file
    plan_file="$TMPD/plan-$tag.txt"
    base=$(boot_bits "$kernel" "$tag-base" "$BASE_WORDS") || { bad "$tag: baseline boot printed no mode vector"; return; }
    python3 tools/bootwords/plan.py plan . "$LIMIT" > "$plan_file"
    while read -r b bit_b specs; do
        [ -n "$b" ] || continue
        has_bit "$base" "$bit_b" && continue
        boot_bits "$kernel" "$tag-$b" "$BASE_WORDS $b" > "$TMPD/bits-$tag-$b" 2>/dev/null &
        running=$((running + 1))
        if [ "$running" -ge "$JOBS" ]; then
            wait -n
            running=$((running - 1))
        fi
    done < "$plan_file"
    wait
    while read -r b bit_b specs; do
        [ -n "$b" ] || continue
        has_bit "$base" "$bit_b" && continue
        check_group "$tag" "$base" "$b" "$bit_b" "$specs"
    done < "$plan_file"
    FAILED_IN_RUN=$((fail - bad_before))
}

echo "== 1. kernel (whole-word matching) =="
if bash tools/build-kernel.sh "$TMPD/new.elf" > "$TMPD/new.log" 2>&1; then
    ok "kernel built"
else
    bad "kernel build"
    tail -8 "$TMPD/new.log" | sed 's/^/        /'
    summary_emit "$pass" "$fail" 1
    exit 1
fi

echo "== 2. every chosen word alone: own mode on, neighbour off =="
FAILED_IN_RUN=0
run_pairs "$TMPD/new.elf" new
[ "$FAILED_IN_RUN" -eq 0 ] && ok "no neighbour word fired" || bad "$FAILED_IN_RUN neighbour checks failed"

echo "== 3. counter-proof: substring scanner (the old behaviour) must be caught =="
OLD="$TMPD/old"
mkdir -p "$OLD"
cp -al . "$OLD/tree" 2>/dev/null || cp -a . "$OLD/tree"
rm -rf "$OLD/tree/.git"
rm -f "$OLD/tree/kernel/lib/cmdword.fi"
sed -e 's/^fn starts_word(hay: u64, at: u64) -> bool {$/fn starts_word(hay: u64, at: u64) -> bool {\n    return true/' \
    -e 's/^fn ends_word(needle: u64, n: u64, after: u64) -> bool {$/fn ends_word(needle: u64, n: u64, after: u64) -> bool {\n    return true/' \
    kernel/lib/cmdword.fi > "$OLD/tree/kernel/lib/cmdword.fi"
if (cd "$OLD/tree" && bash tools/build-kernel.sh "$TMPD/old.elf" > "$TMPD/oldb.log" 2>&1); then
    ok "counter-proof kernel built"
    before=$fail
    pass_before=$pass
    FAILED_IN_RUN=0
    run_pairs "$TMPD/old.elf" old > "$TMPD/old-out.txt"
    caught=$(grep -c 'switched on its neighbour' "$TMPD/old-out.txt")
    fail=$before
    pass=$pass_before
    if [ "$caught" -ge 3 ]; then
        ok "substring scanner caught: $caught neighbour words fired"
    else
        bad "substring scanner NOT caught (only $caught neighbour words fired)"
    fi
else
    bad "counter-proof kernel build"
    tail -8 "$TMPD/oldb.log" | sed 's/^/        /'
fi

summary_emit "$pass" "$fail" 150
