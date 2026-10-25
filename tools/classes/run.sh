#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there" || ok "$3"; }
num() {
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "${value:-}" ]; then bad "$name: no number (want $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"; else bad "$name: $value, want $op $want"; fi
}
D=$(mktemp -d)
NS=cls-$$
V0=cl0-$$
V1=cl1
OSUM_IP=10.9.0.2
HOST_IP=10.9.0.1
QPORT=$(( 14000 + ($$ % 400) * 2 ))
BPORT=$(( QPORT + 1 ))
BRPID=""
QPID=""
cleanup() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    [ -n "$QPID" ] && kill "$QPID" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    rm -rf "$D"
}
trap cleanup EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
finish() { echo "CLASSES: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }

echo "== 1. build =="
PROGS="sh cat echo netmeter"
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; finish; }
./tools/build-kernel.sh "$D/k0.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; finish; }
cat > "$D/s.sh" <<'EOS'
echo ==DRIVERS==
cat /proc/drivers
netmeter 3
echo ==END==
EOS
python3 tools/osum/mkfs.py build "$D/d.img" 20000 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
    $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
    "/t/s.sh=$D/s.sh" > "$D/mkfs.txt" 2>&1 || tail -3 "$D/mkfs.txt"
num "ethreg.ops_for is in the kernel" "$(nm "$D/k0.img.elf" 2>/dev/null | grep -c 'ethreg__ops_for')" ge 1
for fn in tx_frame_on rx_take_on poll_on present_on ready_on init_dispatch link_up_on hwstat_on irq_kind_on kill_cards resume_cards; do
    num "netdev.$fn calls the table through a pointer (indirect call)" \
        "$(objdump -d --no-show-raw-insn --disassemble=_F0.netdev__$fn "$D/k0.img.elf" 2>/dev/null | grep -c 'call.*\*')" ge 1
done
for chip in r8169 e1000 virtio usbnet wlan_net; do
    num "netdev.fi has no direct $chip operation call left" \
        "$(grep -cE "\b$chip\.[a-z_0-9]+_on\(" kernel/net/netdev.fi)" eq 0
done
for cls in r8169 e1000 virtio usbnet wlan; do
    num "ethreg registers the ${cls}_class table" "$(grep -c "${cls}_class.ops()" kernel/drv/net/ethreg.fi)" eq 1
done
num "netdev.fi has no per-kind chain on KIND_E1000 / KIND_VIRTIO left in the operation set" \
    "$(grep -cE 'return (e1000|virtio)\.' kernel/net/netdev.fi)" eq 0

runvm() {
    local name=$1 words=$2; shift 2
    cp "$D/d.img" "$D/d-$name.img"
    timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$D/k0.img" -m 512 \
        -device qemu-xhci -append "osum vfs usb $words script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 "$@" >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}
NETDEV=(-netdev user,id=n0)
runvm rtl "nic" "${NETDEV[@]}" -device rtl8139,netdev=n0,mac=52:54:00:aa:bb:cc
runvm rtlno "nic noclass" "${NETDEV[@]}" -device rtl8139,netdev=n0,mac=52:54:00:aa:bb:cc
runvm rtlbad "nic badclass" "${NETDEV[@]}" -device rtl8139,netdev=n0,mac=52:54:00:aa:bb:cc
runvm e1k "nic" "${NETDEV[@]}" -device e1000,netdev=n0,mac=52:54:00:aa:bb:cc
runvm e1knc "nic noclass" "${NETDEV[@]}" -device e1000,netdev=n0,mac=52:54:00:aa:bb:cc
runvm vio "nic" "${NETDEV[@]}" -device virtio-net-pci,netdev=n0,mac=52:54:00:aa:bb:cc
runvm vionc "nic noclass" "${NETDEV[@]}" -device virtio-net-pci,netdev=n0,mac=52:54:00:aa:bb:cc
runvm usbn "nic usbpoll" "${NETDEV[@]}" -device usb-net,netdev=n0,mac=52:54:00:aa:bb:cc
runvm usbnc "nic usbpoll noclass" "${NETDEV[@]}" -device usb-net,netdev=n0,mac=52:54:00:aa:bb:cc
runvm nonic "nic" -nic none
[ -n "${CLASSES_DUMP:-}" ] && cp "$D"/*.klar "$CLASSES_DUMP"/

echo "== 2. class column + built-in bind state =="
has "$D/rtl.klar" "r8169 pci 10ec:*/0200 found=1 state=bound err=- class=net-eth" "rtl: r8169 row bound, class=net-eth"
has "$D/rtl.klar" "e1000 pci 8086:*/0200 found=0 state=absent err=- class=net-eth" "rtl: e1000 row absent, class=net-eth"
has "$D/rtl.klar" "iwl pci 8086:*/0280 found=0 state=absent err=- class=net-wlan" "rtl: iwl row class=net-wlan"
has "$D/rtl.klar" "nvme pci *:*/0108 found=0 state=absent err=- class=block" "rtl: nvme row class=block"
has "$D/rtl.klar" "hda pci *:*/0403 found=0 state=absent err=- class=audio" "rtl: hda row class=audio"
has "$D/rtl.klar" "vmsvga pci 15ad:0405/0300 found=" "rtl: vmsvga row present"
has "$D/rtl.klar" "class=display" "rtl: a display class row exists"
has "$D/rtl.klar" "xhci pci *:*/0c03.30 found=1" "rtl: legacy row prefix still valid"
has "$D/rtl.klar" "drv=r8169 src=builtin bind=bound" "rtl: /proc/drivers device line shows bind=bound for the built-in"
hasnot "$D/rtl.klar" "drv=r8169 src=builtin bind=failed" "rtl: device line is not failed"
num "rtl: class-calls net-eth counted through the table" "$(grep -aoE '^# class-calls net-eth=[0-9]+' "$D/rtl.klar" | tail -1 | cut -d= -f2)" ge 5

echo "== 3. counter-proofs =="
hasnot "$D/nonic.klar" "r8169 pci 10ec:*/0200 found=0 state=bound" "no NIC: r8169 row is not bound"
has "$D/nonic.klar" "r8169 pci 10ec:*/0200 found=0 state=absent" "no NIC: r8169 row absent"
hasnot "$D/nonic.klar" "# class-calls net-eth" "no NIC: no dispatch through the net-eth table"
has "$D/e1k.klar" "e1000 pci 8086:*/0200 found=1 state=bound err=- class=net-eth" "e1000 NIC: e1000 row bound"
num "e1000 NIC: class-calls net-eth counted through the e1000 table" "$(grep -aoE '^# class-calls net-eth=[0-9]+' "$D/e1k.klar" | tail -1 | cut -d= -f2)" ge 5
has "$D/e1k.klar" "netdev: c0=e1000" "e1000 NIC: netdev picked e1000"
has "$D/e1k.klar" "r8169 pci 10ec:*/0200 found=0 state=absent" "e1000 NIC: r8169 row absent"
has "$D/e1knc.klar" "e1000 pci 8086:*/0200 found=1 state=failed err=init failed class=net-eth" "e1000 noclass: row failed with its reason"
hasnot "$D/e1knc.klar" "# class-calls net-eth" "e1000 noclass: no dispatch counted"
has "$D/vio.klar" "virtio-net pci 1af4:*/0200 found=1 state=bound err=- class=net-eth" "virtio NIC: row bound, class=net-eth"
has "$D/vio.klar" "netdev: c0=virtio-net" "virtio NIC: netdev picked virtio-net"
num "virtio NIC: class-calls net-eth counted" "$(grep -aoE '^# class-calls net-eth=[0-9]+' "$D/vio.klar" | tail -1 | cut -d= -f2)" ge 5
has "$D/vionc.klar" "virtio-net pci 1af4:*/0200 found=1 state=failed err=init failed class=net-eth" "virtio noclass: row failed with its reason"
hasnot "$D/vionc.klar" "# class-calls net-eth" "virtio noclass: no dispatch counted"
has "$D/usbn.klar" "usb-net usb usb class=02 found=? state=bound err=- class=net-eth" "usb-net: row bound, class=net-eth"
has "$D/usbn.klar" "netdev: c0=usbnet" "usb-net: netdev picked usbnet"
num "usb-net: class-calls net-eth counted" "$(grep -aoE '^# class-calls net-eth=[0-9]+' "$D/usbn.klar" | tail -1 | cut -d= -f2)" ge 5
has "$D/usbnc.klar" "usb-net usb usb class=02 found=? state=failed err=init failed class=net-eth" "usb-net noclass: row failed with its reason"
num "usb-net: tray link state (NG_LINK) is up" "$(grep -a '^netmeter: start' "$D/usbn.klar" | grep -aoE 'link=[0-9]+' | tail -1 | cut -d= -f2)" eq 1
num "usb-net noclass: tray link state is down" "$(grep -a '^netmeter: start' "$D/usbnc.klar" | grep -aoE 'link=[0-9]+' | tail -1 | cut -d= -f2)" eq 0
hasnot "$D/usbnc.klar" "# class-calls net-eth" "usb-net noclass: no dispatch counted"
hasnot "$D/rtlno.klar" "r8169 pci 10ec:*/0200 found=1 state=bound" "noclass: r8169 row is not bound"
has "$D/rtlno.klar" "r8169 pci 10ec:*/0200 found=1 state=failed err=init failed class=net-eth" "noclass: r8169 row failed with its reason"
hasnot "$D/rtlno.klar" "# class-calls net-eth" "noclass: no dispatch counted"
has "$D/rtlbad.klar" "r8169 pci 10ec:*/0200 found=1 state=bound" "badclass: init still goes through the table"

echo "== 4. traffic through the table =="
for t in ip gcc python3; do command -v "$t" >/dev/null 2>&1 || { echo "   skipped traffic: $t missing"; finish; }; done
ip netns del "$NS" 2>/dev/null
if ! ip netns add "$NS" 2>/dev/null; then echo "   skipped traffic: no network namespaces"; finish; fi
ip netns del "$NS" 2>/dev/null
gcc -O2 -o "$D/bridge" tools/net/bridge.c 2>"$D/gcc.err" && ok "bridge builds" || { bad "bridge"; head -3 "$D/gcc.err"; finish; }
wire_up() {
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    ip netns add "$NS"
    ip link add "$V0" type veth peer name "$V1"
    ip link set "$V1" netns "$NS"
    ip netns exec "$NS" ip addr add "$HOST_IP/24" dev "$V1"
    ip netns exec "$NS" ip link set "$V1" up
    ip netns exec "$NS" ip link set lo up
    ip link set "$V0" up
    ethtool -K "$V0" tx off rx off tso off gso off gro off >/dev/null 2>&1
    ip netns exec "$NS" ethtool -K "$V1" tx off rx off tso off gso off gro off >/dev/null 2>&1
}
wire_down() { ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null; }
bridge_up() { "$D/bridge" "$V0" "$BPORT" "$QPORT" 2>"$D/br.log" & BRPID=$!; sleep 0.4; }
bridge_down() { [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null; wait "$BRPID" 2>/dev/null; BRPID=""; sleep 0.2; }
await_line() {
    local i
    for i in $(seq 1 $(( ${3:-20} * 5 ))); do
        [ -f "$1" ] && grep -qaF "$2" "$1" && return 0
        sleep 0.2
    done
    return 1
}
ping_run() {
    local name=$1 words=$2 model=${3:-rtl8139} out="$D/ping-$1.txt"
    wire_up; bridge_up
    rm -f "$out"
    ( timeout 220 qemu-system-x86_64 -kernel "$D/k0.img" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 nic nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=0 nwait=900 $words" \
        -serial "file:$out" -display none -no-reboot \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "$model,netdev=n0,id=nic0,mac=52:54:00:aa:bb:cc" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 ) &
    QPID=$!
    await_line "$out" "nic: netd=" 25
    sleep 3
    ip netns exec "$NS" ping -c 20 -i 0.1 -W 2 "$OSUM_IP" > "$D/pingout-$name.txt" 2>&1
    wait "$QPID" 2>/dev/null; QPID=""
    bridge_down; wire_down
    local got
    got=$(grep -oE '[0-9]+ received' "$D/pingout-$name.txt" | grep -oE '^[0-9]+')
    echo "${got:-0}"
}
got=$(ping_run good "")
num "good: ping -c 20 replies through the r8169 table" "$got" ge 19
has "$D/ping-good.txt" "netdev: c0=r8169" "good: netdev picked r8169"
got=$(ping_run bad "badclass")
num "badclass: replies with the transmit hook swapped" "$got" eq 0
has "$D/ping-bad.txt" "netdev: c0=r8169" "badclass: the card was still found"
got=$(ping_run none "noclass")
num "noclass: replies without a table" "$got" eq 0
for pair in e1000:e1000 virtio-net-pci:virtio-net; do
    model=${pair%%:*}; kname=${pair##*:}
    got=$(ping_run "g-$kname" "" "$model")
    num "$kname: ping -c 20 replies through the table" "$got" ge 19
    has "$D/ping-g-$kname.txt" "netdev: c0=$kname" "$kname: netdev picked $kname"
    got=$(ping_run "b-$kname" "badclass" "$model")
    num "$kname badclass: replies with the transmit hook swapped" "$got" eq 0
    got=$(ping_run "n-$kname" "noclass" "$model")
    num "$kname noclass: replies without a table" "$got" eq 0
done
echo "== 5. counter-proof: usbnet_class without link_up reports a down link =="
MUT=kernel/drv/net/usbnet_class.fi
cp "$MUT" "$D/usbnet_class.orig"
trap 'cp "$D/usbnet_class.orig" "$MUT"; cleanup' EXIT
sed -i '/o.link_up = usbnet.up_on/d' "$MUT"
./tools/build-kernel.sh "$D/k1.img" --stufe 0 > "$D/k1.txt" 2>&1 && ok "mutated kernel builds" || { bad "mutated kernel"; tail -5 "$D/k1.txt"; }
cp "$D/usbnet_class.orig" "$MUT"
if [ -s "$D/k1.img" ]; then
    mv "$D/k0.img" "$D/k0.keep"; mv "$D/k0.img.elf" "$D/k0.keep.elf" 2>/dev/null
    cp "$D/k1.img" "$D/k0.img"
    runvm usbmut "nic usbpoll" "${NETDEV[@]}" -device usb-net,netdev=n0,mac=52:54:00:aa:bb:cc
    num "mutated kernel: tray link state is down (counter-proof)" "$(grep -a '^netmeter: start' "$D/usbmut.klar" | grep -aoE 'link=[0-9]+' | tail -1 | cut -d= -f2)" eq 0
fi
finish
