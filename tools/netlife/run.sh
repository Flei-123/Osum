#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
TREE=${NETLIFE_TREE:-$HERE}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$TREE"
export FIRNLIB="$TREE/lib"
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
bash tools/sync/build.sh "$T/bin" 0 sh sleep echo cat dhcp > "$T/b.txt" 2>&1 || { tail "$T/b.txt"; exit 1; }
./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 || { tail "$T/k.txt"; exit 1; }
cat > "$T/s.sh" <<'SCRIPT'
echo ==START==
dhcp dauer t1=12 &
sleep 22
echo ==R1==
cat /etc/resolv.conf
echo ==R1END==
echo junk > /etc/resolv.conf
sleep 14
echo ==R2==
cat /etc/resolv.conf
echo ==R2END==
sleep 40
echo ==LOG==
cat /var/log/net.log
echo ==LOGEND==
echo ==END==
SCRIPT
python3 tools/osum/mkfs.py build "$T/d.img" 8000 /bin/ /t/ /etc/ /var/ /var/log/ /var/jarvis/ \
    /bin/sh="$T/bin/sh.elf" /bin/sleep="$T/bin/sleep.elf" /bin/echo="$T/bin/echo.elf" \
    /bin/cat="$T/bin/cat.elf" /bin/dhcp="$T/bin/dhcp.elf" /t/s.sh="$T/s.sh" > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; exit 1; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
timeout 260 qemu-system-x86_64 -accel $ACC -kernel "$T/k.img" -m 256 \
    -append "osum nokbd nosched noproc nofs noring3 nic nip=169.254.10.1/16 nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
    -serial "file:$T/s.txt" -display none -no-reboot \
    -drive "file=$T/d.img,format=raw,if=ide,index=0" \
    -netdev user,id=n0 -device e1000,netdev=n0,mac=52:54:00:aa:bb:cc \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
LC_ALL=C tr -cd '\11\12\15\40-\176' < "$T/s.txt" > "$T/s.klar"
[ -n "${NETLIFE_KEEP:-}" ] && cp "$T/s.klar" "$NETLIFE_KEEP"
sect() { sed -n "/==$1==/,/==$1END==/p" "$T/s.klar"; }
sect R1 > "$T/r1.txt"; sect R2 > "$T/r2.txt"; sect LOG > "$T/log.txt"
ok=0; fail=0
check() { if [ "$2" = "1" ]; then ok=$((ok+1)); echo "OK   $1"; else fail=$((fail+1)); echo "FAIL $1"; fi; }
has() { grep -aq -- "$2" "$1" && echo 1 || echo 0; }
check "lease acquired" "$(has "$T/s.klar" 'dhcp: ack ip=')"
check "lease renewed at least 3 times" "$([ "$(grep -ac 'dhcp: lease renewed' "$T/s.klar")" -ge 3 ] && echo 1 || echo 0)"
check "address set exactly once" "$([ "$(grep -ac 'dhcp: gesetzt ip=' "$T/s.klar")" -eq 1 ] && echo 1 || echo 0)"
check "resolv.conf has nameserver after lease" "$(has "$T/r1.txt" '^nameserver ')"
check "resolv.conf has fallback after lease" "$(has "$T/r1.txt" '^fallback ')"
check "resolv.conf repaired after being clobbered" "$(has "$T/r2.txt" '^nameserver ')"
check "net.log has start event" "$(has "$T/log.txt" ' start')"
check "net.log has lease event with ip" "$(has "$T/log.txt" ' lease ip=')"
check "net.log has renewed event" "$(has "$T/log.txt" ' renewed ')"
check "net.log has dns-fixed event" "$(has "$T/log.txt" ' dns-fixed ')"
check "net.log has status line with jarvisd state" "$(has "$T/log.txt" ' status .*jarvisd=')"
check "net.log lines carry wall clock and uptime" "$(has "$T/log.txt" '^t=[0-9]* up=[0-9]* ')"
echo "NETLIFE: ok=$ok fail=$fail"
[ "$fail" -eq 0 ]
