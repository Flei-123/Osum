#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/rpc/run.sh -- REQUEST/REPLY ON THE BUS (kernel/user/rpc.fi), MEASURED.
#
#   bash tools/rpc/run.sh          (heavy: /root/jarvis/bin/heavy bash tools/rpc/run.sh)
#   RPC_KEEP=1 ...                 keep the temp dir (guest logs)
#
# A real Osum guest under QEMU: two services (/bin/rpcd as rpc.a, rpc.b)
# and a client (/bin/rpcc) that runs the battery of docs/RPC.md section 6:
#
#   T01 sync echo               T09 big reply 3000 B (54 frames)
#   T02 service error + text    T10 reply over the limit -> E_TOOBIG
#   T03 unknown verb            T11 request over the limit -> E_TOOBIG
#   T04 no such service         T12 8 in flight, 9th refused, all 8 arrive
#   T05 timeout (200 ms)        T13 cancel, late answer dropped + counted
#   T06 late answer dropped     T14 service dies mid-call -> E_GONE < 0.6 s
#   T07 async, out of order     T15 afterwards: E_NOSVC
#   T08 kernel-stamped pid      T16 1000 calls, every answer checked
#
# Sections: 1 build  2 one core  3 four cores + 3 parallel stress clients
# 4 counter-proof "nobus": the client fails fast and says so (no hang).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

TMPD=$(mktemp -d)
[ -n "${RPC_KEEP:-}" ] || trap 'rm -rf "$TMPD"' EXIT
BLOCKS=8000
PROGS="sh ls cat echo sleep rpcd rpcc"
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
[ -x vendor/firn/bin/firnc ] || { echo "RPC: firnc0 missing"; exit 1; }
mkdir -p "$TMPD/bin"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "firnc0 builds $(echo $PROGS | wc -w) programs (rpc.fi compiled into rpcd + rpcc)"
else
    bad "the programs do not build"; sed 's/^/        /' "$TMPD/b.txt" | head -20
    echo "RPC: $pass passed, $fail failed"; exit 1
fi
note "rpcd $(stat -c%s "$TMPD/bin/rpcd.elf") B, rpcc $(stat -c%s "$TMPD/bin/rpcc.elf") B"
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then
    ok "the kernel builds"
else
    bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'
    echo "RPC: $pass passed, $fail failed"; exit 1
fi
command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "RPC: skipped, qemu missing"; echo "RPC: $pass passed, $fail failed"; exit 0; }

image() { # <image> <script>
    local img=$1 script=$2 p
    local -a A=(build "$img" $BLOCKS /lib/
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf"
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ /var/log/)
    for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
    A+=("/t/s.sh=$script")
    python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 \
        || { echo "mkfs failed"; tail -3 "$TMPD/mkfs.txt"; }
}
run() { # <image> <name> <smp> <seconds> [bus|nobus]
    local img=$1 nm=$2 smp=$3 secs=$4 busflag=${5:-bus}
    timeout "$secs" qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp "$smp" \
        -kernel "$TMPD/k0.img" -m 512 \
        -append "osum vfs nokbd $busflag script=sh /t/s.sh;exit" \
        -serial "file:$TMPD/$nm.txt" -display none -no-reboot \
        -drive "file=$img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$TMPD/$nm.txt" > "$TMPD/$nm.klar" 2>/dev/null || true
}
check_battery() { # <log> <label>
    local f=$1 l=$2 n bad_n
    n=$(grep -c '^T[0-9][0-9] ok' "$f")
    bad_n=$(grep -c '^T[0-9][0-9] FAIL' "$f")
    if [ "$n" = 16 ] && [ "$bad_n" = 0 ]; then ok "$l: T01..T16 all ok"; else
        bad "$l: $n ok, $bad_n FAIL"; grep '^T[0-9][0-9] FAIL' "$f" | sed 's/^/        /'
    fi
    grep -q '^RPCC: 16 passed, 0 failed' "$f" && ok "$l: summary line" || bad "$l: no summary line"
}
lat() { # <log> -> µs per call
    local t; t=$(grep -a '^LAT calls=1000 ticks=' "$1" | head -1 | sed 's/.*ticks=//')
    [ -n "$t" ] && echo $((t * 10)) || echo -1
}

echo "== 2. one core =="
cat > "$TMPD/s1.sh" <<'EOS'
rpcd rpc.a 30000 &
rpcd rpc.b 30000 &
sleep -m 400
rpcc
echo rc=$?
EOS
image "$TMPD/d1.img" "$TMPD/s1.sh"
run "$TMPD/d1.img" r1 1 240
check_battery "$TMPD/r1.klar" "1 core"
U1=$(lat "$TMPD/r1.klar")
[ "$U1" -gt 0 ] && ok "latency 1 core: $U1 us per call (1000 sync calls, tick resolution 10 ms)" || bad "no latency line"
grep -q '^rc=0' "$TMPD/r1.klar" && ok "rpcc exits 0" || bad "rpcc exit code not 0"

if [ -n "${RPC_QUICK:-}" ]; then   # debug: section 2 only (one boot)
    echo "RPC: $pass passed, $fail failed (quick, sections 3+4 skipped)"; [ "$fail" = 0 ]; exit
fi
echo "== 3. four cores, three parallel stress clients =="
cat > "$TMPD/s4.sh" <<'EOS'
rpcd rpc.a 30000 &
rpcd rpc.b 30000 &
sleep -m 400
rpcc stress rpc.a 300 > /tmp/st1.txt &
rpcc stress rpc.a 300 > /tmp/st2.txt &
rpcc stress rpc.a 300 > /tmp/st3.txt &
sleep -m 6000
echo ==STRESS==
cat /tmp/st1.txt
cat /tmp/st2.txt
cat /tmp/st3.txt
echo ==BATTERY==
rpcc
echo rc=$?
EOS
image "$TMPD/d4.img" "$TMPD/s4.sh"
run "$TMPD/d4.img" r4 4 300
S=$(grep -ac '^STRESS 300 of 300 ok' "$TMPD/r4.klar")
[ "$S" = 3 ] && ok "3 parallel clients x 300 calls: every answer exact (900/900)" || { bad "stress: only $S of 3 clients complete and exact"; grep -a STRESS "$TMPD/r4.klar" | sed 's/^/        /'; }
part=$(awk '/==BATTERY==/{f=1;next} f' "$TMPD/r4.klar")
echo "$part" > "$TMPD/r4.bat"
check_battery "$TMPD/r4.bat" "4 cores"
U4=$(lat "$TMPD/r4.bat")
[ "$U4" -gt 0 ] && ok "latency 4 cores: $U4 us per call" || bad "no latency line (4 cores)"

echo "== 4. counter-proof: no bus =="
cat > "$TMPD/sn.sh" <<'EOS'
rpcc
echo rc=$?
EOS
image "$TMPD/dn.img" "$TMPD/sn.sh"
T0=$(date +%s)
run "$TMPD/dn.img" rn 1 120 nobus
T1=$(date +%s)
grep -aq '^T01 FAIL' "$TMPD/rn.klar" && ok "without a bus T01 fails (the check measures something)" || bad "T01 did not fail without a bus"
grep -aq '^RPCC: ' "$TMPD/rn.klar" && [ $((T1 - T0)) -lt 100 ] && ok "and rpcc ends with its summary in $((T1 - T0)) s: no hang" || bad "rpcc hangs or prints no summary without a bus"

echo "RPC: latency us/call: 1 core $U1, 4 cores $U4"
echo "RPC: $pass passed, $fail failed"
[ "$fail" = 0 ]
