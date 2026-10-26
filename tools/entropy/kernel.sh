#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/entropy/kernel.sh -- the kernel generator, measured in QEMU (R-005 stage 2).
#
#   bash tools/entropy/kernel.sh
#
# 1. statistics over 1 MiB from the running kernel (chi-square, monobit, runs, serial correlation,
#    entropy, repeated blocks); the battery is first shown to reject five bad streams
# 2. the same without RDRAND/RDSEED (-cpu qemu64): jitter alone must initialise the generator
# 3. two boots give different output
# 4. counter-proofs: no source at all -> getrandom(GRND_NONBLOCK) = -EAGAIN and /proc/random says
#    not-initialised; stuck jitter is detected by the health test and earns no credit; `fixedrand`
#    is rejected by the battery; bad getrandom flags give -EINVAL
# 5. /dev/random write mixes without credit
# 6. seed file on a disk root: absent -> written, then loaded with credit and replaced (different
#    bytes), a damaged file is refused; a RAM root is reported as not persistent
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/qemu.sh
OUT=${OUT:-$(mktemp -d /tmp/entropy-kernel.XXXXXX)}
[ "${KEEP:-0}" = 1 ] || trap 'rm -rf "$OUT"' EXIT
mkdir -p "$OUT"
CC=${FIRNC:-vendor/firn/bin/firnc}
PROGS="sh ls cat echo rndtest"
QUIET="nokbd nosched noproc nofs noring3"
SAMPLE=1048576

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hat() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hatnicht() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there" || ok "$3"; }
field() { grep -a -m1 "^$2 " "$1" | sed "s/^$2 //" | tr -d '\r'; }

for t in qemu-system-x86_64 python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "ENTROPY-KERNEL: skipped, $t missing"; exit 0; }
done
python3 -c "import numpy, scipy" 2>/dev/null || { echo "ENTROPY-KERNEL: skipped, numpy/scipy missing"; exit 0; }

echo "== 0. the battery itself =="
python3 -I tools/entropy/stats.py selfcheck 2>/dev/null | while read -r l; do echo "  $l"; done
python3 -I tools/entropy/stats.py selfcheck >/dev/null 2>&1 && ok "the battery accepts good and rejects five bad streams" || bad "the battery is vacuous"

echo
echo "== 1. build: kernel, programs, disk =="
bash vendor/firn/fetch-firnc.sh > "$OUT/firnc.log" 2>&1 && ok "the pinned compiler" || bad "fetch-firnc.sh"
bash tools/build-kernel.sh "$OUT/k.mb" > "$OUT/kernel.log" 2>&1 && ok "kernel built" || { bad "build-kernel.sh"; tail -15 "$OUT/kernel.log"; exit 1; }
as --64 -o "$OUT/crt.o" kernel/user/crt.s
SPEC="/bin/ /dev/ /proc/ /system/ /tmp/"
for p in $PROGS; do
    "$CC" "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1 || { bad "$p does not build"; head -5 "$OUT/$p.err"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start -o "$OUT/$p.elf" "$OUT/crt.o" "$OUT/$p.o" 2> "$OUT/$p.lderr" || { bad "ld $p"; exit 1; }
    strip --strip-all "$OUT/$p.elf"
    SPEC="$SPEC /bin/$p=$OUT/$p.elf"
done
python3 tools/osum/mkfs.py build "$OUT/disk.img" 4096 $SPEC > "$OUT/mkfs.txt" 2>&1 && ok "OFS disk with $(echo $PROGS | wc -w) programs" || { bad "mkfs.py"; exit 1; }

boot() { # name disk cpu words script
    timeout 300 $QEMU_X86 -kernel "$OUT/k.mb" -m 256 -cpu "$3" -append "osum vfs $QUIET $4 script=$5" \
        -serial "file:$OUT/$1.txt" -display none -no-reboot \
        -drive "file=$2,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    echo $? > "$OUT/$1.rc"
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' -e 's/\r//g' "$OUT/$1.txt" 2>/dev/null
}
fresh() { cp "$OUT/disk.img" "$OUT/live-$1.img"; echo "$OUT/live-$1.img"; }

echo
echo "== 2. statistics over $SAMPLE octets from the running kernel =="
boot s_hsw "$(fresh a)" Haswell "" "cat /proc/random;rndtest hex $SAMPLE;cat /proc/random;exit"
[ "$(cat "$OUT/s_hsw.rc")" = 21 ] && ok "Haswell (RDRAND, no RDSEED): the machine comes up" || bad "s_hsw exit code $(cat "$OUT/s_hsw.rc")"
python3 -I tools/entropy/stats.py expect-pass "$OUT/s_hsw.txt" "Haswell" 2>/dev/null && pass=$((pass+1)) || { fail=$((fail+1)); python3 -I tools/entropy/stats.py expect-pass "$OUT/s_hsw.txt" "Haswell" 2>&1 | tail -12; }
hat "$OUT/s_hsw.txt" "state ready" "/proc/random says ready"
hat "$OUT/s_hsw.txt" "cpu.rdrand 1" "the CPU has RDRAND"
hat "$OUT/s_hsw.txt" "cpu.rdseed 0" "and no RDSEED"
bits=$(grep -a "^entropy_bits " "$OUT/s_hsw.txt" | head -1 | awk '{print $2}')
[ "${bits:-0}" -ge 256 ] && ok "credited entropy ${bits} bits (>= 256)" || bad "credited entropy '${bits}' < 256"

boot s_bdw "$(fresh b)" Broadwell "" "cat /proc/random;rndtest hex $SAMPLE;exit"
python3 -I tools/entropy/stats.py expect-pass "$OUT/s_bdw.txt" "Broadwell (RDSEED)" 2>/dev/null && pass=$((pass+1)) || { fail=$((fail+1)); python3 -I tools/entropy/stats.py expect-pass "$OUT/s_bdw.txt" "Broadwell" 2>&1 | tail -12; }
hat "$OUT/s_bdw.txt" "cpu.rdseed 1" "Broadwell has RDSEED"

echo
echo "== 3. no CPU generator: the jitter alone initialises (-cpu qemu64) =="
boot s_q64 "$(fresh c)" qemu64 "" "cat /proc/random;rndtest hex $SAMPLE;exit"
[ "$(cat "$OUT/s_q64.rc")" = 21 ] && ok "qemu64: the machine comes up" || bad "s_q64 exit code $(cat "$OUT/s_q64.rc")"
hat "$OUT/s_q64.txt" "cpu.rdrand 0" "no RDRAND"
hat "$OUT/s_q64.txt" "state ready" "still ready"
jb=$(grep -a "^source.jitter_bits " "$OUT/s_q64.txt" | head -1 | awk '{print $2}')
[ "${jb:-0}" -ge 256 ] && ok "the jitter source gave ${jb} bits" || bad "jitter bits '${jb}'"
python3 -I tools/entropy/stats.py expect-pass "$OUT/s_q64.txt" "qemu64 (jitter only)" 2>/dev/null && pass=$((pass+1)) || { fail=$((fail+1)); python3 -I tools/entropy/stats.py expect-pass "$OUT/s_q64.txt" "qemu64" 2>&1 | tail -12; }
boot s_q64b "$(fresh d)" qemu64 "" "rndtest hex 8192;exit"
python3 -I tools/entropy/stats.py differ "$OUT/s_q64.txt" "qemu64 jitter-only reboot" "$OUT/s_q64b.txt" 2>/dev/null && pass=$((pass+1)) || { fail=$((fail+1)); echo "  FAIL qemu64 reboot output identical"; }
boot s_hsw2 "$(fresh e)" Haswell "" "rndtest hex 8192;exit"
python3 -I tools/entropy/stats.py differ "$OUT/s_hsw.txt" "Haswell reboot" "$OUT/s_hsw2.txt" 2>/dev/null && pass=$((pass+1)) || { fail=$((fail+1)); echo "  FAIL Haswell reboot output identical"; }

echo
echo "== 4. counter-proofs =="
boot c_none "$(fresh f)" qemu64 "randnojitter" "cat /proc/random;rndtest peek;rndtest hex 64 nonblock;rndtest peek badflag;exit"
hat "$OUT/c_none.txt" "state not-initialised" "no source: /proc/random says not-initialised"
hat "$OUT/c_none.txt" "RND getrandom -11" "getrandom(GRND_NONBLOCK) = -EAGAIN, no weak bytes"
grep -qaE "^RND [0-9a-f]{32}" "$OUT/c_none.txt" && bad "weak bytes came out before initialisation" || ok "no output bytes before the generator is initialised"
hat "$OUT/c_none.txt" "RND getrandom -22" "unknown getrandom flags = -EINVAL"
hat "$OUT/c_none.txt" "jitter.mode off" "the jitter source is off"
boot c_stuck "$(fresh g)" qemu64 "randjitterstuck" "cat /proc/random;rndtest peek;exit"
hat "$OUT/c_stuck.txt" "state not-initialised" "stuck jitter: not initialised"
hat "$OUT/c_stuck.txt" "source.jitter_bits 0" "the health test refuses every stuck sample: no credit"
fails=$(field "$OUT/c_stuck.txt" "jitter.failures")
[ "${fails:-0}" -gt 0 ] && ok "health test failures counted: ${fails}" || bad "no health failures counted ('${fails}')"
hat "$OUT/c_stuck.txt" "RND getrandom -11" "and getrandom says -EAGAIN"
boot c_notrust "$(fresh h)" Haswell "randnotrustcpu" "cat /proc/random;rndtest peek;exit"
hat "$OUT/c_notrust.txt" "source.cpu_bits 0" "randnotrustcpu: the CPU generator earns no credit"
hat "$OUT/c_notrust.txt" "state ready" "the jitter initialises anyway"
boot c_fixed "$(fresh i)" Haswell "fixedrand" "rndtest hex $SAMPLE;exit"
python3 -I tools/entropy/stats.py expect-fail "$OUT/c_fixed.txt" "fixedrand" 2>/dev/null && pass=$((pass+1)) || { fail=$((fail+1)); echo "  FAIL fixedrand accepted"; }

echo
echo "== 5. /dev/random write mixes, without credit =="
boot w "$(fresh j)" qemu64 "randnojitter" "rndtest write;cat /proc/random;exit"
hat "$OUT/w.txt" "RND wrote 64" "64 octets written to /dev/random"
hat "$OUT/w.txt" "state not-initialised" "and the write alone does not initialise the generator"
hat "$OUT/w.txt" "source.seed_bits 0" "no credit for a write"

echo
echo "== 6. the seed file =="
SD="$(fresh k)"
boot z1 "$SD" Haswell "randnotrustcpu randnojitter" "cat /proc/random;exit"
hat "$OUT/z1.txt" "seed.file absent" "first boot: no seed file"
hat "$OUT/z1.txt" "state not-initialised" "without CPU credit and jitter nothing initialises it"
boot z2 "$SD" Haswell "" "cat /proc/random;rndtest dump /system/RANDSEED;exit"
hat "$OUT/z2.txt" "seed.file absent" "second boot with sources: still no file to load"
hat "$OUT/z2.txt" "seed.saved 1" "but a seed file was written"
boot z3 "$SD" Haswell "randnotrustcpu randnojitter" "cat /proc/random;rndtest dump /system/RANDSEED;exit"
hat "$OUT/z3.txt" "seed.file loaded" "next boot: the seed file is loaded"
hat "$OUT/z3.txt" "source.seed_bits 128" "with 128 bits of credit"
hat "$OUT/z3.txt" "state not-initialised" "which alone is not enough to initialise (256 needed)"
boot z4 "$SD" qemu64 "randnojitter" "cat /proc/random;rndtest dump /system/RANDSEED;exit"
hat "$OUT/z4.txt" "seed.file loaded" "again loaded"
a=$(grep -a "^RND " "$OUT/z2.txt" | grep -v "RND getrandom\|RND wrote" | tr -d '\n')
b=$(grep -a "^RND " "$OUT/z3.txt" | grep -v "RND getrandom\|RND wrote" | tr -d '\n')
c=$(grep -a "^RND " "$OUT/z4.txt" | grep -v "RND getrandom\|RND wrote" | tr -d '\n')
if [ -n "$a" ] && [ "$a" != "$b" ] && [ "$b" != "$c" ]; then ok "the file is replaced at every boot (never used twice)"; else bad "the seed file was not replaced ('${a:0:24}' '${b:0:24}' '${c:0:24}')"; fi
boot z5 "$SD" Haswell "" "echo broken > /system/RANDSEED;exit"
boot z6 "$SD" qemu64 "randnojitter" "cat /proc/random;exit"
hat "$OUT/z6.txt" "seed.file invalid" "a damaged file is refused"
hat "$OUT/z6.txt" "source.seed_bits 0" "and earns no credit"

echo
echo "== 7. a RAM root is reported as not persistent =="
if [ -f tools/install/build.sh ]; then
    IMG="$OUT/img"
    mkdir -p "$IMG"
    bash tools/install/build.sh "$IMG" > "$OUT/install-build.log" 2>&1 \
        && ok "install image built" || { bad "tools/install/build.sh"; tail -5 "$OUT/install-build.log"; }
    head -c $((64 * 1024 * 1024)) /dev/zero > "$IMG/ziel0.img"
    cp "$IMG/ziel0.img" "$IMG/ziel.img"
    OUT="$IMG" bash tools/install/oneshot.sh r iso "cat /proc/random;exit" 240 > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' -e 's/\r//g' "$IMG/r.txt" 2>/dev/null
    hat "$IMG/r.txt" "seed.file ram-root-not-persistent-no-use" "the RAM root says so"
    hat "$IMG/r.txt" "seed.saved 0" "and nothing is written"
fi

echo
echo "== 8. measurements: time to initialise, throughput, before and after =="
for cpu in Haswell Broadwell qemu64; do
    boot m_$cpu "$(fresh m$cpu)" $cpu "" "cat /proc/random;rndtest bench 4194304;rndtest bench 4194304;exit"
    us=$(grep -a "^ready_after_us " "$OUT/m_$cpu.txt" | head -1 | awk '{print $2}')
    line=$(grep -a "^RND bench " "$OUT/m_$cpu.txt" | tail -1)
    bytes=$(echo "$line" | awk '{print $3}'); ns=$(echo "$line" | awk '{print $4}')
    if [ -n "$us" ] && [ -n "$ns" ] && [ "$ns" -gt 0 ]; then
        ok "$cpu: initialised $us us after the clock started; getrandom 4 MiB in $((ns / 1000000)) ms = $((bytes * 1000 / (ns / 1000) / 1000)) MB/s (new)"
    else
        bad "$cpu: no measurement ('$us' '$line')"
    fi
done
if [ -n "${BASE_TREE:-}" ] && [ -f "$BASE_TREE/tools/build-kernel.sh" ]; then
    (cd "$BASE_TREE" && bash tools/build-kernel.sh "$OUT/k-base.mb" > "$OUT/kernel-base.log" 2>&1) && ok "baseline kernel built from $BASE_TREE" || bad "baseline kernel build"
    cp "$OUT/k.mb" "$OUT/k-new.mb"
    cp "$OUT/k-base.mb" "$OUT/k.mb"
    boot m_base "$(fresh mbase)" Haswell "" "rndtest bench 4194304;rndtest bench 4194304;exit"
    cp "$OUT/k-new.mb" "$OUT/k.mb"
    line=$(grep -a "^RND bench " "$OUT/m_base.txt" | tail -1)
    bytes=$(echo "$line" | awk '{print $3}'); ns=$(echo "$line" | awk '{print $4}')
    if [ -n "$ns" ] && [ "$ns" -gt 0 ]; then
        ok "Haswell: getrandom 4 MiB in $((ns / 1000000)) ms = $((bytes * 1000 / (ns / 1000) / 1000)) MB/s (before: the old collector and ChaCha20)"
    else
        bad "baseline measurement missing ('$line')"
    fi
fi

echo
echo "=================================================================="
echo "  ENTROPY-KERNEL: $pass passed, $fail failed"
echo "=================================================================="
[ "$fail" = 0 ] || exit 1
exit 0
