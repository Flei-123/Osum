#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/mem/run.sh -- ROUND MEM: 512 MiB WAS NOT A PROPERTY OF THE MACHINE.
#
# It was a property of two constants:
#
#   1. `kstate.BITMAP_BYTES` is 0x4000, and `mem.scan` computed the
#      number of frames as `BITMAP_BYTES * 8`. That is 131072 frames,
#      512 MiB, no matter what the boot loader reported.
#   2. `kernel/boot.s` builds ONE page directory, 512 entries of 2 MiB.
#      That is ONE gibioctet of identity mapping -- and above it the old
#      kernel did not waste memory, it DIED. Measured on `main`
#      (3389fbd) with `-m 2G`:
#
#          *** EXCEPTION 14 #PF  err=0x0  cr2=0x7ffe1adc
#
#      err=0x0 is "page not there", and 0x7ffe1adc is where QEMU puts
#      the ACPI tables just under two gibioctets.
#
# Everything below is measured with the SAME kernel image and nothing
# but `-m` different. That is the whole design of this runner: if a
# number moves, only the amount of RAM moved it.
#
#   1. WHAT THE KERNEL SEES vs WHAT IT MANAGES. `mmap:` says what the
#      loader reported, `frames:` says how many frames the bitmap
#      covers. On `main` the second number was 131072 in every single
#      run; here it follows the first.
#   2. WHAT THE BITMAP COSTS. One bit per 4 KiB frame is 32 KiB per
#      gibioctet. The line `mem: bitmap=<n> octets` says it, and this
#      runner checks the arithmetic against the reported size instead of
#      trusting the number.
#   3. THAT THE FRAMES ARE REALLY THERE. `memprobe` takes the highest
#      free frame the memory map covers, writes two words into it and
#      reads them back. At 64 GiB that address is 0x103ffff000. This is
#      the measurement the old kernel could not survive.
#   4. THAT NOTHING GETS LOST. `memstress` takes two hundred thousand
#      frames, writes a value derived from the address of each one into
#      it, walks the chain back, checks every value and gives every
#      frame back. Free frames before and after MUST be the same number.
#   5. THAT 512 MiB DID NOT GET WORSE. The small machines are measured
#      as well, and the whole existing acceptance of the project runs at
#      -m 128 and -m 256.
#
# Usage:  bash tools/mem/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL

export FIRNLIB="$(pwd)/lib"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { # name value op expected
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: no number (expected $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, expected $op $want"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' is missing"; }

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "vendor/firn/fetch-firnc.sh failed"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "MEM: skipped, qemu-system-x86_64 is not available"
    exit 0
fi

echo "== 1. one kernel image, and nothing but -m changes =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/build.txt" 2>&1 \
    && ok "$(cat "$TMPD/build.txt")" \
    || { bad "the kernel does not build"; sed 's/^/        /' "$TMPD/build.txt" | head -10; \
         echo "MEM: $pass passed, $fail failed"; exit 1; }

run() { # size extra-words -> writes $TMPD/<size>.txt, returns the qemu exit code
    local size=$1 extra=${2:-}
    timeout 600 $QEMU_X86 -kernel "$TMPD/k.mb" -m "$size" \
        -append "$extra nokbd nosched noproc nofs noring3" \
        -serial "file:$TMPD/$size.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    local rc=$?
    tr -d '\000' < "$TMPD/$size.txt" > "$TMPD/$size.clean"
    mv "$TMPD/$size.clean" "$TMPD/$size.txt"
    return $rc
}
field() { grep -a -m1 "^$2" "$1" | grep -oaE "$3=[0-9a-fx]+" | head -1 | cut -d= -f2; }

# What the loader reported, and what the kernel made of it.
declare -A COVERED FREE BITMAP MAPPED USABLE RC
for m in 128 256 512 1G 2G 8G 16G 64G; do
    run "$m" "memstress"
    RC[$m]=$?
    F="$TMPD/$m.txt"
    USABLE[$m]=$(grep -a -m1 '^mmap:' "$F" | grep -oaE '[0-9]+ KiB usable' | grep -oaE '^[0-9]+')
    COVERED[$m]=$(grep -a -m1 '^frames:' "$F" | grep -oaE '^frames: [0-9]+' | grep -oaE '[0-9]+')
    FREE[$m]=$(grep -a -m1 '^frames:' "$F" | grep -oaE 'covered, [0-9]+' | grep -oaE '[0-9]+')
    BITMAP[$m]=$(field "$F" 'mem: ' 'bitmap')
    MAPPED[$m]=$(field "$F" 'mem: ' 'mapped')
done

echo
echo "== 2. every one of them reaches the end of the kernel =="
for m in 128 256 512 1G 2G 8G 16G 64G; do
    if [ "${RC[$m]}" -eq 21 ] && grep -qa '^kernel: done' "$TMPD/$m.txt"; then
        ok "-m $m: the kernel shut itself down (exit 21)"
    else
        bad "-m $m: QEMU exit ${RC[$m]}, expected 21"
        grep -a -A3 'EXCEPTION' "$TMPD/$m.txt" | head -5 | sed 's/^/        /'
    fi
done
for m in 2G 8G 16G 64G; do
    grep -qa 'EXCEPTION' "$TMPD/$m.txt" \
        && bad "-m $m: an exception in the run" \
        || ok "-m $m: not one exception (on main this run died at cr2=0x7ffe1adc)"
done

echo
echo "== 3. what is reported, and what is managed =="
printf '        %-6s %14s %12s %12s %10s %8s\n' \
    "-m" "usable KiB" "frames" "free" "bitmap" "GiB map"
for m in 128 256 512 1G 2G 8G 16G 64G; do
    printf '        %-6s %14s %12s %12s %10s %8s\n' \
        "$m" "${USABLE[$m]}" "${COVERED[$m]}" "${FREE[$m]}" \
        "${BITMAP[$m]}" "${MAPPED[$m]}"
done
# THE POINT OF THE WHOLE ROUND: this number used to be 131072 in every
# single line of that table.
num "frames covered at -m 512 (the old ceiling)" "${COVERED[512]}" eq 131072
num "frames covered at -m 2G" "${COVERED[2G]}" gt 131072
num "frames covered at -m 8G" "${COVERED[8G]}" gt 2000000
num "frames covered at -m 64G" "${COVERED[64G]}" gt 16000000
num "free frames at -m 64G (64 GiB is 16777216 frames)" "${FREE[64G]}" gt 16700000
num "and the small machine has not gained anything it does not have" \
    "${COVERED[128]}" eq 131072

echo
echo "== 4. what the bitmap costs =="
# 1 bit per 4 KiB frame = 32 KiB per GiB. Checked against the number the
# kernel printed, not taken from it.
for m in 2G 8G 64G; do
    c=${COVERED[$m]}
    want=$(( (c + 7) / 8 ))
    b=${BITMAP[$m]}
    if [ "$b" = "$want" ]; then
        ok "-m $m: bitmap $b octets = ceil($c frames / 8), exactly one bit per frame"
    else
        bad "-m $m: bitmap $b octets, one bit per frame would be $want"
    fi
done
kib=$(( ${BITMAP[64G]} / 1024 ))
gib=${MAPPED[64G]}
num "-m 64G: bitmap in KiB" "$kib" lt 2200
ok "-m 64G: that is $(( ${BITMAP[64G]} / gib / 1024 )) KiB per mapped gibioctet (1 bit per 4 KiB frame is 32)"
num "-m 512: the bitmap is still the 16384 octets of the kernel data area" \
    "${BITMAP[512]}" eq 16384

echo
echo "== 5. the identity map follows the memory map =="
num "-m 128: gibioctets mapped (boot.s maps one, and one is enough)" "${MAPPED[128]}" eq 1
num "-m 512: gibioctets mapped" "${MAPPED[512]}" eq 1
num "-m 2G: gibioctets mapped" "${MAPPED[2G]}" eq 2
num "-m 8G: gibioctets mapped (the map reaches 0x240000000 -- there is a hole under 4 GiB)" \
    "${MAPPED[8G]}" eq 9
num "-m 64G: gibioctets mapped" "${MAPPED[64G]}" eq 65

echo
echo "== 6. THE FRAMES ARE REALLY THERE =="
# The highest free frame of the machine, written and read back. This is
# the measurement the old kernel could not survive.
for m in 512 2G 8G 64G; do
    at=$(field "$TMPD/$m.txt" 'memprobe:' 'at')
    hit=$(field "$TMPD/$m.txt" 'memprobe:' 'ok')
    if [ "$hit" = "1" ]; then
        ok "-m $m: the highest free frame ($at) was written and read back"
    else
        bad "-m $m: memprobe at $at came back ok=$hit"
    fi
done
hi=$(field "$TMPD/64G.txt" 'memprobe:' 'at')
[ "$hi" = "0x103ffff000" ] \
    && ok "-m 64G: and that address is 0x103ffff000 -- 65 gibioctets up" \
    || bad "-m 64G: memprobe address $hi, expected 0x103ffff000"

echo
echo "== 7. NOTHING GETS LOST =="
for m in 128 512 2G 8G 16G 64G; do
    F="$TMPD/$m.txt"
    want=$(field "$F" 'memstress:' 'want')
    got=$(field "$F" 'memstress:' 'got')
    before=$(field "$F" 'memstress:' 'before')
    low=$(field "$F" 'memstress:' 'low')
    after=$(field "$F" 'memstress:' 'after')
    badn=$(field "$F" 'memstress:' 'bad')
    seen=$(field "$F" 'memstress:' 'seen')
    if [ -z "$before" ]; then bad "-m $m: memstress said nothing"; continue; fi
    if [ "$before" = "$after" ]; then
        ok "-m $m: $got frames taken and given back, free before = free after ($before)"
    else
        bad "-m $m: free before $before, after $after -- $(( before - after )) frames lost"
    fi
    [ "$got" = "$want" ] || bad "-m $m: asked for $want frames, got $got"
    [ "$badn" = "0" ] || bad "-m $m: $badn frames came back with the wrong check word"
    [ "$seen" = "$got" ] || bad "-m $m: the chain led back to $seen of $got frames"
    # And it really did take them: while everything was held, the count
    # has to be lower by exactly that many.
    if [ "$low" = "$(( before - got ))" ]; then
        ok "-m $m: and while they were held the count was lower by exactly $got"
    else
        bad "-m $m: while held: $low, expected $(( before - got ))"
    fi
done

echo
echo "== 8. GEGENPROBE: without the word nothing runs =="
run 2G ""
rc=$?
[ "$rc" -eq 21 ] && ok "-m 2G without 'memstress': still exit 21" || bad "exit $rc"
grep -qa '^memstress:' "$TMPD/2G.txt" \
    && bad "the stress test ran without being asked" \
    || ok "and not one line of the stress test -- it is a word, not the default"
grep -qa '^mem: bitmap=' "$TMPD/2G.txt" \
    && ok "the two numbers of this round are printed in every boot" \
    || bad "the 'mem: bitmap=' line is missing"

echo
echo "MEM: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
