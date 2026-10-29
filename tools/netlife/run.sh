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
SV=$T/sv; mkdir -p "$SV"
cat > "$T/dreh_sv.txt" <<EOT
warteauf 'dhcp: renewing lease' || 240
warte 45
EOT
DESIGNBUILD="$SV/build" bash tools/design/eh6.sh "$SV/o" res=1280x800 accel=$ACC netz=ja tafel=nein \
    progs="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq dhcp" drehbuch="$T/dreh_sv.txt" > "$SV/o.log" 2>&1
SS="$SV/o/serial.txt"
LC_ALL=C tr -cd '\11\12\15\40-\176' < "$SS" > "$SV/s.klar" 2>/dev/null
check "supervisor start: daemon enters the renewal loop" "$([ "$(grep -ac 'dhcp: renewing lease, t1=' "$SV/s.klar")" -ge 1 ] && echo 1 || echo 0)"
check "supervisor start: one lease only, no restart after it" "$([ "$(grep -ac 'dhcp: ack ip=' "$SV/s.klar")" -eq 1 ] && echo 1 || echo 0)"
check "supervisor start: no dhcp respawn by the supervisor" "$([ "$(grep -ac 'desk: shell dhcp respawn' "$SV/s.klar")" -eq 0 ] && echo 1 || echo 0)"
argc_ok=1
python3 -I - kernel/ui/kgui.fi <<'PY' || argc_ok=0
import re, sys
src = open(sys.argv[1], "rb").read().decode("latin-1")
for m in re.finditer(r'desk_spawn_svc\(state, 2, \(&(\w+)\[0\]\) as u64,\s*\(&(\w+)\[0\]\) as u64, (\d+), (\d+)\)', src):
    decl = re.search(r'var ' + m.group(2) + r': \[u8; \d+\] = "([^"]*)"', src)
    words = decl.group(1).split("\\0")
    n = len([w for w in words if w])
    if n != int(m.group(4)):
        sys.exit(1)
PY
check "kgui dhcp spawn: argc equals the number of argument words" "$argc_ok"
echo "NETLIFE: ok=$ok fail=$fail"
[ "$fail" -eq 0 ]
