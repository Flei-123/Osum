#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d)
SRV=""
trap '[ -n "$SRV" ] && kill "$SRV" 2>/dev/null; [ -n "${UPLSW_KEEP:-}" ] && { mkdir -p "$UPLSW_KEEP"; cp "$T"/*.klar "$T"/srv*.log "$UPLSW_KEEP"/ 2>/dev/null; }; rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }
command -v qemu-system-x86_64 >/dev/null || { echo "UPLINKSWITCH: skipped, no qemu"; exit 0; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
. tools/lib/firnenv.sh
HOSTIP=$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
[ -n "$HOSTIP" ] || { echo "UPLINKSWITCH: no host address"; exit 1; }
SUM=$(python3 -c 'print(sum(((i*7+3)&255) for i in range(65536)))')
NEWIP=10.0.2.77
NEWNUM=$(( (10<<24) | (0<<16) | (2<<8) | 77 ))

bash tools/sync/build.sh "$T/bin" 0 sh echo cat sleep ping dhcp uplswitch > "$T/b.txt" 2>&1 \
    && ok "programs build" || { bad "programs build"; tail "$T/b.txt"; echo "UPLINKSWITCH: $pass ok, $fail fail"; exit 1; }
KNEW="${UPLSW_KERNEL:-}"
if [ -z "$KNEW" ]; then
    ./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 \
        && ok "kernel builds" || { bad "kernel build"; tail -30 "$T/k.txt"; echo "UPLINKSWITCH: $pass ok, $fail fail"; exit 1; }
    KNEW="$T/k.img"
fi

start_server() {
    rm -f "$T/port"
    python3 -I tools/uplinkswitch/server.py "$T/port" "$T/$1" &
    SRV=$!
    for _ in $(seq 1 50); do [ -s "$T/port" ] && break; sleep 0.1; done
    PORT=$(cat "$T/port")
}
stop_server() { kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null; SRV=""; }

BINS=(/bin/sh="$T/bin/sh.elf" /bin/echo="$T/bin/echo.elf" /bin/cat="$T/bin/cat.elf" /bin/sleep="$T/bin/sleep.elf"
      /bin/ping="$T/bin/ping.elf" /bin/dhcp="$T/bin/dhcp.elf" /bin/uplswitch="$T/bin/uplswitch.elf")
printf 'nameserver 192.168.1.1\nfallback 1.1.1.1\n' > "$T/resolv.old"

run_readdr() { # name kernel
    local n=$1 k=$2
    start_server "srv_$n.log"
    printf 'echo ==START==\ndhcp\nuplswitch %s %s %s\necho ==ALIVE==\n' "$HOSTIP" "$PORT" "$NEWIP" > "$T/s_$n.sh"
    bash tools/mkfsfi/mkfs.sh build "$T/$n.img" 8000 /bin/ /t/ /etc/ /proc/ /dev/ "${BINS[@]}" \
        "/t/s.sh=$T/s_$n.sh" > "$T/$n.mkfs" 2>&1 || { tail -3 "$T/$n.mkfs"; return 1; }
    timeout 240 qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "$k" -m 256 -nodefaults \
        -append "osum vfs nic nip=169.254.10.1/16 nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
        -serial "file:$T/$n.txt" -display none -no-reboot \
        -netdev user,id=n0,net=10.0.2.0/24 -device e1000,netdev=n0 \
        -drive "file=$T/$n.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$n.txt" > "$T/$n.klar"
    sleep 1
    stop_server
}

echo "== A: readdress with an open connection (e1000, osum_netset as after an uplink switch) =="
run_readdr a "$KNEW"; A="$T/a.klar"; S="$T/srv_a.log"
has "$A" 'dhcp: ack ip=10.0.2.15' "lease on e1000"
has "$A" 'uplswitch: udp before=7' "bound UDP socket answers before the switch"
grep -aqE 'uplswitch: conn1 open=[0-9]+$' "$A" && ok "conn1 open" || bad "conn1 not open"
has "$A" 'uplswitch: same-address netset rc=0' "same-address netset accepted"
has "$A" 'uplswitch: conn1 after same-address netset recv=1' "same-address netset keeps conn1"
has "$A" 'uplswitch: readdr rc=0' "readdress accepted"
has "$A" "uplswitch: address now=$NEWNUM" "new address active"
grep -aqE 'inet: readdr epoch=[0-9]+ rebound=[1-9][0-9]* stale=[1-9]' "$A" && ok "kernel: new epoch, UDP rebound, conn1 stale" || bad "kernel: epoch line missing or wrong"
has "$A" 'uplswitch: stale conn1 recv= errno=104' "stale conn1 recv gives ECONNRESET"
has "$A" 'uplswitch: stale conn1 send= errno=104' "stale conn1 send gives ECONNRESET"
has "$A" 'uplswitch: conn2 bytes=65536' "conn2 complete after conn1 close"
has "$A" "uplswitch: conn2 sum=$SUM" "conn2 data intact"
has "$A" 'uplswitch: udp after=7' "bound UDP socket answers after the switch"
has "$S" 'big done' "server finished conn2"
hasnot "$S" 'big abort' "server saw no FIN on conn2"
has "$A" '==ALIVE==' "script reached the end"
grep -aiq 'panic\|exception\|#PF\|#GP\|#UD' "$A" && bad "A: panic/exception" || ok "A: no panic/exception"

echo "== U: USB uplink hot plug, resolv.conf follows the uplink lease =="
ADD="monitor device_add usb-net,id=devu1,bus=x0.0,netdev=n1,mac=52:54:00:12:34:99"
printf 'echo ==START==\ndhcp\ncat /etc/resolv.conf\necho ==ALIVE==\n' > "$T/s_u.sh"
bash tools/mkfsfi/mkfs.sh build "$T/u.img" 8000 /bin/ /t/ /etc/ /proc/ /dev/ "${BINS[@]}" \
    "/t/s.sh=$T/s_u.sh" "/etc/resolv.conf=$T/resolv.old" > "$T/u.mkfs" 2>&1 || tail -3 "$T/u.mkfs"
printf 'aufzeile k17: hold\n%s\naufzeile nethot: uplink card=1 kind=usbnet\naufzeile k17: free\n' "$ADD" > "$T/p_u"
timeout 200 qemu-system-x86_64 -accel $ACC -kernel "$KNEW" -m 256 -nodefaults \
    -append "osum vfs nokbd nosched noring3 usb usbhold usbpoll nic rndisonly nip=169.254.10.1/16 nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
    -serial "file:$T/u.txt" -display none -no-reboot \
    -monitor "unix:$T/u.mon,server,nowait" -pidfile "$T/u.pid" \
    -drive "file=$T/u.img,format=raw,if=ide,index=0" \
    -netdev user,id=n0,net=10.0.2.0/24 -device e1000,netdev=n0 -device qemu-xhci,id=x0 -netdev user,id=n1,net=10.0.5.0/24 \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
python3 -I tools/hotplug/monitor.py "$T/u.mon" "$T/u.txt" "$T/p_u" > "$T/u.mon.txt" 2>&1 \
    && ok "U: monitor plan" || bad "U: monitor plan"
for _ in $(seq 1 45); do grep -aq '==ALIVE==' "$T/u.txt" && break; sleep 2; done
[ -f "$T/u.pid" ] && kill "$(cat "$T/u.pid")" 2>/dev/null; wait 2>/dev/null
tr -cd '\11\12\15\40-\176' < "$T/u.txt" > "$T/u.klar"; U="$T/u.klar"
has "$U" 'dhcp: ack ip=10.0.5.15' "U: lease from the USB uplink"
awk '/==START==/{f=1} f' "$U" | grep -aq 'nameserver 10.0.5.3' && ok "U: resolv.conf names the USB uplink DNS" || bad "U: resolv.conf misses 10.0.5.3"
hasnot "$U" 'nameserver 192.168.1.1' "U: old nameserver gone"
has "$U" 'fallback 1.1.1.1' "U: fallback line kept"
has "$U" '==ALIVE==' "U: script reached the end"

mkdir -p "$T/blobs"
python3 -I tools/iwlfh/ref.py gen "$T/blobs" >/dev/null 2>&1 || bad "W: firmware reference generator"
FWPATH=/lib/firmware/intel/iwlwifi/iwlwifi-8265-36.ucode
printf 'ssid OrientFake\npsk orient-fake-pw1\n' > "$T/wlan.conf"
{ echo 'echo ==START=='; for _ in 1 2 3 4 5 6 7 8; do echo 'sleep 6'; done
  echo 'dhcp'; echo 'echo ==RESOLV=='; echo 'cat /etc/resolv.conf'; echo 'cat /proc/wlan'; echo 'echo ==END=='; } > "$T/s_w.sh"

run_wlan() { # name words
    local n=$1 words=$2
    bash tools/mkfsfi/mkfs.sh build "$T/$n.img" 20000 --v3 /bin/ /t/ /etc/ /proc/ /lib/ /lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ \
        "${BINS[@]}" "/t/s.sh=$T/s_w.sh" "$FWPATH=$T/blobs/v7.bin" "/etc/wlan.conf=$T/wlan.conf" "/etc/resolv.conf=$T/resolv.old" > "$T/$n.mkfs" 2>&1 || tail -3 "$T/$n.mkfs"
    timeout 400 qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "$KNEW" -m 512 \
        -append "osum vfs iwlfhtest iwlfhbind $words nic script=sh /t/s.sh;exit" \
        -serial "file:$T/$n.txt" -display none -no-reboot \
        -netdev user,id=n0,net=10.0.2.0/24 -device e1000,netdev=n0 \
        -drive "file=$T/$n.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$n.txt" > "$T/$n.klar"
    awk '/==RESOLV==/{f=1} f' "$T/$n.klar" > "$T/${n}_res.txt"
}

echo "== W: WLAN uplink (wlanfirst), kernel lease DNS lands in resolv.conf =="
run_wlan w wlanfirst; W="$T/w.klar"
has "$W" 'stack wired=1 uplink=1' "W: WLAN card is the uplink"
has "$W" 'dhcp: wlan lease adopted' "W: dhcp adopts the kernel WLAN lease"
grep -aq 'nameserver 192\.168\.77\.' "$T/w_res.txt" && ok "W: resolv.conf names the WLAN lease DNS" || bad "W: resolv.conf has no WLAN DNS"
hasnot "$T/w_res.txt" 'nameserver 192.168.1.1' "W: old nameserver gone"
hasnot "$T/w_res.txt" 'nameserver 10.0.2.3' "W: no e1000 DNS"
has "$T/w_res.txt" 'fallback 1.1.1.1' "W: fallback line kept"
has "$W" '==END==' "W: system keeps running"

echo "== V: WLAN without wlanfirst stays on standby while a wired card is present =="
run_wlan v ""; V="$T/v.klar"
hasnot "$V" 'dhcp: wlan lease adopted' "V: dhcp does not adopt the WLAN lease"
hasnot "$V" 'stack wired=1 uplink=1' "V: WLAN card is not the uplink"
grep -aq 'nameserver 192\.168\.77\.' "$T/v_res.txt" && bad "V: resolv.conf names the WLAN DNS" || ok "V: resolv.conf free of WLAN DNS"
has "$V" '==END==' "V: system keeps running"

if [ "${UPLSW_OLD:-1}" = 1 ]; then
    echo "== control: ${UPLSW_BASE:-origin/main} kernel in case A =="
    mkdir -p "$T/old"; git archive "${UPLSW_BASE:-origin/main}" | tar -x -C "$T/old"
    firnenv_prepare_old_tree "$T/old"
    if (cd "$T/old" && FIRNLIB="$T/old/lib" ./tools/build-kernel.sh "$T/old.img" --stufe 0 > "$T/old.txt" 2>&1); then
        run_readdr ctl "$T/old.img"; C="$T/ctl.klar"
        if grep -aq 'uplswitch: conn2 bytes=65536' "$C" && grep -aq "uplswitch: conn2 sum=$SUM" "$C" \
            && grep -aq 'uplswitch: udp after=7' "$C"; then
            bad "control: old kernel kept conn2 and UDP intact (gate cannot see the bug)"
        else
            ok "control: old kernel breaks conn2 or the bound UDP socket"
        fi
    else bad "control: old kernel did not build"; fi
fi
echo "UPLINKSWITCH: $pass ok, $fail fail"
[ "$fail" -gt 0 ] && exit 1
exit 0
