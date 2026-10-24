#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
OK=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then OK=$((OK+1)); printf '  ok    %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL  %s: want <%s> got <%s>\n' "$1" "$2" "$3"; fi; }
[ -f tools/ecquery/asl/ec.aml ] || ( cd tools/ecquery/asl && iasl ec.asl > /dev/null 2>&1 )
if [ -n "${ECQUERY_IMG:-}" ]; then IMG=$ECQUERY_IMG; else IMG="$D/osum.mb"; nice -n 10 ./tools/build-kernel.sh "$IMG" > /dev/null || { echo "build failed"; exit 1; }; fi
run() {
    local n=$1 extra=$2
    timeout 120 qemu-system-x86_64 -kernel "$IMG" -m 256 -append "acpiev evself evwait blpch $extra noring3 nofs" \
        -acpitable file=tools/ecquery/asl/ec.aml -serial "file:$D/$n.txt" -display none -no-reboot > /dev/null 2>&1 &
    local qp=$!
    for _ in $(seq 1 100); do grep -aq 'ecsim: done' "$D/$n.txt" 2>/dev/null && break; kill -0 $qp 2>/dev/null || break; sleep 1; done
    sleep 1; kill $qp 2>/dev/null; wait $qp 2>/dev/null
}
g() { sed -n '/ecsim: outv/,$p' "$D/$1.txt" | grep -ac -- "$2"; }
echo "== 1. EC query path (ecsim)"
run a "ecsim"
chk "sim finished" 1 "$(g a 'ecsim: done')"
chk "EC device found" 1 "$(g a '^ec found=1')"
chk "ports from _CRS" 1 "$(g a '^ec found=1 data=0x0062 cmd=0x0066')"
chk "_REG(3,1) ran" 1 "$(g a ' reg=1 ')"
chk "query 0x11 -> Notify 0x86 -> brightness up, 0x12 -> down (50 again)" 1 "$(g a 'ecsim: pct=50')"
chk "_Q12 read EC field and wrote EC register" 1 "$(g a 'ecsim: outv=119')"
chk "two queries ran, one missing" 1 "$(g a ' run=2 missing=1 ')"
chk "three queries executed" 1 "$(g a ' queries=3 ')"
chk "last query 0x99" 1 "$(g a ' lastq=0x0099 ')"
chk "acpi notify 0x87 seen as last" 1 "$(g a '^sci .*last=0x0087')"
chk "WMI + HPQ devices counted" 1 "$(g a '^hw wmi=1 hpq=1 ')"
echo "== 2. counter-proof (noec)"
run b "ecsim noec"
chk "sim finished" 1 "$(g b 'ecsim: done')"
chk "no EC found" 1 "$(g b '^ec found=0')"
chk "_Q12 never ran: EC register untouched" 1 "$(g b 'ecsim: outv=0')"
chk "no EC query ran" 1 "$(g b ' queries=0 ')"
chk "diag shows driver disabled" 1 "$(g b 'noec=1')"
realkey() {
    local n=$1 extra=$2
    timeout 120 qemu-system-x86_64 -kernel "$IMG" -m 256 -append "acpiev evself evwait blpch ecsim $extra noring3 nofs" \
        -acpitable file=tools/ecquery/asl/ec.aml -serial "file:$D/$n.txt" -display none -no-reboot -monitor "unix:$D/$n.mon,server,nowait" > /dev/null 2>&1 &
    local qp=$!
    for _ in $(seq 1 100); do grep -aq 'hksim: done' "$D/$n.txt" 2>/dev/null && break; sleep 0.2; done
    echo "sendkey mail" | timeout 5 socat - "unix-connect:$D/$n.mon" > /dev/null 2>&1
    for _ in $(seq 1 100); do grep -aq 'ecsim: done' "$D/$n.txt" 2>/dev/null && break; kill -0 $qp 2>/dev/null || break; sleep 1; done
    sleep 1; kill $qp 2>/dev/null; wait $qp 2>/dev/null
}
echo "== 3. raw scancode diagnostics (QEMU sendkey mail = E0 6C)"
realkey c ""
chk "raw ring shows E0 6C" 1 "$(g c '^raw: .*0xe0 0x6c')"
chk "kbd irq counted" 1 "$(g c '^kbd raw=[1-9]')"
realkey d "nokirq nokbdpoll"
chk "counter-proof: no raw bytes without IRQ/poll" 1 "$(g d '^kbd raw=0 ')"
echo; echo "ecquery: $OK ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
