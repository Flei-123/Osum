#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hwnet/run.sh -- ROUND HWNET: THE SAME KERNEL ON TWO DIFFERENT CHIPS.
#
# Round K8 measured Osum's network against the Linux kernel over a
# virtio-net card. Everything it proved is still true and none of it says
# anything about a machine you can touch: virtio-net exists only under a
# hypervisor. This round put a second driver under the same stack
# (`kernel/e1000.fi`) and a layer between them that decides WHICH driver
# a card gets (`kernel/netdev.fi`).
#
# So the measurement is: RUN THE SAME THING TWICE, once with
# `-device virtio-net-pci` and once with `-device e1000`, and hold the
# two columns of numbers against each other. Anything that only works on
# one of them is a driver bug; anything that works on both is the layer
# doing its job.
#
# THE WIRE is the one round K8 built (`tools/net/bridge.c`): QEMU's UDP
# socket backend on one side, an AF_PACKET bridge into a veth pair on the
# other, and a network namespace with the Linux kernel in it. `/dev/net/tun`
# does not exist in the container this repository is measured in.
#
#   Osum in QEMU <--virtio-net or e1000--> QEMU <--UDP on loopback-->
#   tools/net/bridge <--AF_PACKET--> veth v0 | v1 <--> Linux in `hwnet-$$`
#
# WHAT IS NOT MEASURED HERE, said plainly: NO PHYSICAL CARD. The only
# e1000 this repository has ever talked to is QEMU's 82540EM. Everything
# about a chip on a real board is a statement about a data sheet, and
# `docs/REALHW.md` marks every one of those as such.
#
# THE COUNTER-CHECKS, per card, each of them a run in which the
# measurement has to collapse:
#
#   no `nic`   the same image never touches the card: ping gets nothing
#   nicnobm    the bus master bit is taken away: the chip may answer
#              registers but may not fetch a descriptor
#   rtl8139    a card this kernel has NO driver for: it has to be named
#              with its numbers, not passed over in silence
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}

NS=hwnet-$$
V0=hw0-$$
V1=hw1
OSUM_IP=10.9.0.2
HOST_IP=10.9.0.1
QPORT=$(( 12000 + ($$ % 400) * 2 ))
BPORT=$(( QPORT + 1 ))

TMPD=$(mktemp -d)
BRPID=""
QPID=""
DHPID=""
cleanup() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    [ -n "$QPID" ] && kill "$QPID" 2>/dev/null
    [ -n "$DHPID" ] && kill "$DHPID" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    rm -rf "$TMPD"
}
trap cleanup EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { # name value op expected
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "${value:-}" ]; then bad "$name: no number found (expected $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, expected $op $want"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' is missing"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' should not be there" || ok "$3"; }
val() { grep -aoE "^nic: $2=[0-9]+" "$1" 2>/dev/null | tail -1 | cut -d= -f2; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
for t in qemu-system-x86_64 ip gcc nc python3 busybox; do
    command -v "$t" >/dev/null 2>&1 || { echo "HWNET: skipped, $t is not available"; exit 0; }
done
ip netns del "$NS" 2>/dev/null
if ! ip netns add "$NS" 2>/dev/null; then
    echo "HWNET: skipped, network namespaces are not available here"
    exit 0
fi
ip netns del "$NS" 2>/dev/null

# =====================================================================
echo "== 1. the build, with both compilers =="
# =====================================================================
if bash tools/hwnet/build.sh "$TMPD/s0" 0 > "$TMPD/b0.txt" 2>&1; then
    ok "firnc0: kernel with netdev.fi + e1000.fi, and seven programs"
else
    bad "firnc0 does not build it"; sed 's/^/        /' "$TMPD/b0.txt" | head -10
    echo "HWNET: $pass passed, $fail failed"; exit 1
fi
if bash tools/hwnet/build.sh "$TMPD/s1" 1 > "$TMPD/b1.txt" 2>&1; then
    ok "firnc1: the same, out of the compiler written in Firn"
else
    bad "firnc1 does not build it"; sed 's/^/        /' "$TMPD/b1.txt" | head -10
fi
K="$TMPD/s0/k.mb"
D="$TMPD/s0/disk.img"

# The driver is part of the freestanding kernel: no libc, no runtime and
# not one `syscall` instruction in ring 0.
undef=$(nm -u "$TMPD/s0/k.o" 2>/dev/null | awk '{print $NF}' | sed '/^$/d' \
        | grep -vE '^(osum_panic|kdata)$')
[ -z "$undef" ] && ok "k.o: no undefined name other than osum_panic and kdata" \
                || bad "k.o: undefined symbols: $undef"
n=$(nm "$TMPD/s0/k.o" 2>/dev/null | grep -cE 'e1000__init_on|netdev__probe')
num "e1000.fi and netdev.fi really are in the image (symbols)" "$n" ge 2

gcc -O2 -o "$TMPD/bridge" tools/net/bridge.c 2>"$TMPD/gcc.err" \
    && ok "tools/net/bridge.c: the UDP/AF_PACKET wire is built" \
    || { bad "bridge.c does not compile"; head -5 "$TMPD/gcc.err"; }

# ------------------------------------------------------------ the wire
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
bridge_up() { "$TMPD/bridge" "$V0" "$BPORT" "$QPORT" 2>"$TMPD/br.log" & BRPID=$!; sleep 0.4; }
bridge_down() { [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null; wait "$BRPID" 2>/dev/null; BRPID=""; sleep 0.2; }

# qemu_bg <nic-device> <append> <out> [extra args...]
qemu_bg() {
    local nic=$1 append=$2 out=$3
    shift 3
    rm -f "$out"
    ( timeout 200 qemu-system-x86_64 -kernel "$K" -m 256 -append "$append" \
        -serial "file:$out" -display none -no-reboot "$@" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "$nic,netdev=n0,mac=52:54:00:aa:bb:cc" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
      echo $? > "$out.rc" ) &
    QPID=$!
}
qemu_wait() { wait "$QPID" 2>/dev/null; QPID=""; }
await_line() { # file text seconds
    local i
    for i in $(seq 1 $(( ${3:-20} * 5 ))); do
        [ -f "$1" ] && grep -qaF "$2" "$1" && return 0
        sleep 0.2
    done
    return 1
}

BASE="nokbd nosched noproc nofs noring3"
NETARGS="nic nip=$OSUM_IP/24 ngw=$HOST_IP"

# =====================================================================
echo "== 2. the bus decides which driver, and says so =="
# =====================================================================
for pair in "virtio-net-pci:virtio-net:1af4:1000" "e1000:e1000:8086:100e"; do
    dev=${pair%%:*}; rest=${pair#*:}; name=${rest%%:*}
    rest=${rest#*:}; ven=${rest%%:*}; did=${rest#*:}
    wire_up; bridge_up
    qemu_bg "$dev" "osum $BASE $NETARGS nsvc=0 nwait=60" "$TMPD/bus-$dev.txt"
    qemu_wait
    bridge_down; wire_down
    F="$TMPD/bus-$dev.txt"
    has "$F" "$ven:$did class=02:00:00 network" "$dev: the PCI scan finds $ven:$did on class 02:00"
    has "$F" "netdev: c0=$name" "$dev: netdev picks the driver '$name' out of the table"
    has "$F" "mac=52:54:00:aa:bb:cc" \
        "$dev: the Ethernet address was READ OUT OF THE CHIP and is the one QEMU was given"
    n=$(grep -aoE 'nic: netd=[0-9]+' "$F" | cut -d= -f2)
    num "$dev: the network task exists" "${n:-0}" ge 1
done

echo "   counter-check: a chip this kernel has NO driver for"
wire_up; bridge_up
qemu_bg "rtl8139" "osum $BASE $NETARGS nsvc=0 nwait=60" "$TMPD/bus-rtl.txt"
qemu_wait
bridge_down; wire_down
R="$TMPD/bus-rtl.txt"
has "$R" "netdev: no driver for 0x10ec:0x8139" \
    "the unknown card is NAMED WITH ITS NUMBERS -- the sentence a real board needs"
has "$R" "nic: no device" "and the kernel says the stack has nothing under it"
hasnot "$R" "netdev: c0=" "no driver claimed a card it cannot drive"

# =====================================================================
echo "== 3. the same acceptance on both chips =="
# =====================================================================
dd if=/dev/urandom of="$TMPD/quarter.bin" bs=1024 count=256 2>/dev/null
for dev in virtio-net-pci e1000; do
    echo "   --- $dev ---"

    # --- ICMP. THE THREE SECONDS ARE MEASURED AND NOT A COMFORT PAUSE:
    # a frame that reaches an e1000 before the ring exists is not thrown
    # away by QEMU, it is put aside and retried a second later
    # (`flush_queue_timer`, hw/net/e1000.c), and everything behind it
    # waits with it. Pinged immediately after boot, the first ten
    # requests came back at once, 935 ms late; after a settle they take
    # single milliseconds. Measured, written down, and the same wait is
    # given to both cards so the two columns compare.
    wire_up; bridge_up
    qemu_bg "$dev" "osum $BASE $NETARGS nsvc=0 nwait=1500" "$TMPD/ping-$dev.txt"
    await_line "$TMPD/ping-$dev.txt" "nic: netd=" 25
    sleep 3
    ip netns exec "$NS" ping -c 20 -i 0.1 -W 2 "$OSUM_IP" > "$TMPD/pingout-$dev.txt" 2>&1
    qemu_wait
    bridge_down; wire_down
    got=$(grep -oE '[0-9]+ received' "$TMPD/pingout-$dev.txt" | grep -oE '^[0-9]+')
    num "$dev: ping -c 20 from the Linux kernel, answers" "${got:-0}" ge 19
    rtt=$(grep -oE 'min/avg/max/mdev = [0-9.]+/[0-9.]+' "$TMPD/pingout-$dev.txt" \
          | awk -F'= ' '{print $2}' | cut -d/ -f2)
    [ -n "$rtt" ] && ok "$dev: round trip, average $rtt ms (QEMU/TCG, no KVM)" \
                  || bad "$dev: no round trip time"
    num "$dev: interrupts the chip really raised" "$(val "$TMPD/ping-$dev.txt" irqs)" ge 5
    num "$dev: ICMP messages the stack counted" "$(val "$TMPD/ping-$dev.txt" icmp)" ge 19

    # --- TCP, 256 KiB into Osum
    wire_up; bridge_up
    qemu_bg "$dev" "osum $BASE $NETARGS nsvc=1 nport=7 nbytes=262144" "$TMPD/sink-$dev.txt"
    await_line "$TMPD/sink-$dev.txt" "nic: listening=7" 25
    ip netns exec "$NS" timeout 120 nc -q 1 "$OSUM_IP" 7 < "$TMPD/quarter.bin" >/dev/null 2>&1
    qemu_wait
    bridge_down; wire_down
    S="$TMPD/sink-$dev.txt"
    num "$dev: octets that arrived in Osum" "$(val "$S" octets)" eq 262144
    num "$dev: frames the chip received" "$(val "$S" rx_f)" ge 150
    num "$dev: segments with a bad checksum" "$(val "$S" csum)" eq 0
    num "$dev: retransmissions on a clean wire" "$(val "$S" rexmit)" eq 0
    num "$dev: frames the driver had to drop (ring full)" "$(val "$S" drops)" eq 0
    ok "$dev: throughput Linux -> Osum: $(val "$S" kib_per_s) KiB/s ($(val "$S" us) us for 256 KiB)"

    # --- DHCP, out of a server this repository did not write
    wire_up; bridge_up
    cat > "$TMPD/udhcpd.conf" <<EOF
start 10.9.0.50
end 10.9.0.60
interface $V1
option subnet 255.255.255.0
option router $HOST_IP
option lease 600
lease_file $TMPD/udhcpd.leases
pidfile $TMPD/udhcpd.pid
EOF
    : > "$TMPD/udhcpd.leases"
    ip netns exec "$NS" busybox udhcpd -f "$TMPD/udhcpd.conf" > "$TMPD/udhcpd.log" 2>&1 &
    DHPID=$!
    sleep 0.5
    cp "$D" "$TMPD/live-$dev.img"
    # THE CLIENT IS BOOTED WITH AN ADDRESS IT IS SUPPOSED TO LOSE
    # (10.9.0.9) and with the gateway that also runs the server. That is
    # not a convenience: `kernel/user/dhcp.fi` says in its own header
    # that the vendored stack has no broadcast path OUT -- it resolves a
    # next hop by ARP even for 255.255.255.255 -- so a DHCP server that
    # is not reachable by ARP cannot be talked to at all. Measured here:
    # with `ngw=169.254.1.1`, which nothing answers, the discover never
    # leaves the machine (0 UDP frames on the wire, sniffed). It is a
    # real gap for a real network and it is written down in
    # docs/ROADMAP-UPDATE.md with the three lines it would take.
    qemu_bg "$dev" \
        "osum $BASE nic nip=10.9.0.9/24 ngw=$HOST_IP nsvc=0 nwait=0 script=dhcp;ping -c 2 $HOST_IP;exit" \
        "$TMPD/dhcp-$dev.txt" -drive "file=$TMPD/live-$dev.img,format=raw,if=ide,index=0"
    qemu_wait
    kill "$DHPID" 2>/dev/null; DHPID=""
    bridge_down; wire_down
    H="$TMPD/dhcp-$dev.txt"
    grep -qaE 'dhcp: offer ip=10\.9\.0\.(5[0-9]|60)' "$H" \
        && ok "$dev: an OFFER out of busybox udhcpd -- a server this repository did not write" \
        || bad "$dev: no DHCP offer ($(grep -a 'dhcp:' "$H" | head -2 | tr '\n' ' '))"
    grep -qaE 'dhcp: ack ip=10\.9\.0\.(5[0-9]|60)' "$H" && ok "$dev: and an ACK for it" \
        || bad "$dev: no DHCP ack"
    grep -qaE 'dhcp: (gesetzt|set) ip=10\.9\.0\.(5[0-9]|60)' "$H" \
        && ok "$dev: the client really took the address" \
        || bad "$dev: the client did not take the address"
    hasnot "$H" "dhcp: offer ip=10.9.0.9" "$dev: it was not handed back the address it booted with"
    grep -qaE '^2 (transmitted|packets transmitted), 2 received' "$H" \
        && ok "$dev: and with that address it reaches the gateway (ICMP)" \
        || bad "$dev: it cannot reach the gateway with the address it was given"

    # --- counter-check: the same image, without the word `nic`
    wire_up; bridge_up
    qemu_bg "$dev" "osum $BASE nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=0 nwait=400" "$TMPD/no-$dev.txt"
    sleep 3
    ip netns exec "$NS" ping -c 4 -i 0.3 -W 1 "$OSUM_IP" > "$TMPD/noping-$dev.txt" 2>&1
    qemu_wait
    bridge_down; wire_down
    lost=$(grep -oE '[0-9]+% packet loss' "$TMPD/noping-$dev.txt" | grep -oE '^[0-9]+')
    num "$dev: COUNTER-CHECK without the driver, packets lost" "${lost:-0}" eq 100
    has "$TMPD/no-$dev.txt" "nic: skipped" "$dev: and the kernel says why"

    # --- counter-check: nicnobm
    wire_up; bridge_up
    qemu_bg "$dev" "osum $BASE $NETARGS nicnobm nsvc=0 nwait=400" "$TMPD/nobm-$dev.txt"
    sleep 3
    ip netns exec "$NS" ping -c 4 -i 0.3 -W 1 "$OSUM_IP" > "$TMPD/nobmping-$dev.txt" 2>&1
    qemu_wait
    bridge_down; wire_down
    has "$TMPD/nobm-$dev.txt" "master=0" "$dev: the bus master bit really is off"
    lost=$(grep -oE '[0-9]+% packet loss' "$TMPD/nobmping-$dev.txt" | grep -oE '^[0-9]+')
    num "$dev: COUNTER-CHECK without bus master, packets lost" "${lost:-0}" eq 100
done

# =====================================================================
echo "== 4. the two columns, side by side =="
# =====================================================================
printf '   %-14s %10s %10s %10s %10s\n' chip octets KiB/s rx_f irqs
for dev in virtio-net-pci e1000; do
    S="$TMPD/sink-$dev.txt"
    printf '   %-14s %10s %10s %10s %10s\n' "$dev" \
        "$(val "$S" octets)" "$(val "$S" kib_per_s)" "$(val "$S" rx_f)" "$(val "$S" irqs)"
done

echo "HWNET: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
