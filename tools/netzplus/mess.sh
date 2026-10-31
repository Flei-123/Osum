#!/usr/bin/env bash
#
#   Osum in QEMU <--virtio-net--> QEMU <--UDP auf loopback-->
#   tools/net/bridge <--AF_PACKET--> veth V0 | V1 <--> Linux im
#   Namensraum NS, 10.9.0.1/24; Osum ist 10.9.0.2/24
#
set -uo pipefail

NS=nzp-$$
V0=nz0-$$
V1=v1
OSUM_IP=10.9.0.2
HOST_IP=10.9.0.1
#
QPORT=$(( 5000 + ($$ % 400) * 2 ))
BPORT=$(( QPORT + 1 ))

NZP_BASE=${NZP_BASE:-"nokbd nosched noproc nofs noring3"}

BRPID=""
QPID=""

# ---------------------------------------------------------------- Draht
# wire_up [Verlust Richtung Osum] [Verlust Richtung Linux] [Verzoegerung]
#
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
    local lim=10000
    if [ -n "${1:-}" ] || [ -n "${3:-}" ]; then
        ip netns exec "$NS" tc qdisc add dev "$V1" root netem limit $lim \
            ${1:+loss $1} ${3:+delay $3} >/dev/null 2>&1
    fi
    if [ -n "${2:-}" ] || [ -n "${3:-}" ]; then
        tc qdisc add dev "$V0" root netem limit $lim \
            ${2:+loss $2} ${3:+delay $3} >/dev/null 2>&1
    fi
}

wire_down() {
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
}

bridge_up() {
    "$TMPD/bridge" "$V0" "$BPORT" "$QPORT" 2>"$TMPD/br.log" &
    BRPID=$!
    sleep 0.4
}

bridge_down() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    wait "$BRPID" 2>/dev/null
    BRPID=""
    sleep 0.2
}

# qemu_bg <Abbild> <append> <Ausgabe> [weitere Argumente...]
qemu_bg() {
    local image=$1 append=$2 out=$3
    shift 3
    rm -f "$out" "$out.rc"
    ( timeout "${NZP_TIMEOUT:-180}" $QEMU_X86 -kernel "$image" -m 256 -append "$append" \
        -serial "file:$out" -display none -no-reboot "$@" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "virtio-net-pci,netdev=n0,mac=52:54:00:aa:bb:cc" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
      echo $? > "$out.rc" ) &
    QPID=$!
}

qemu_wait() {
    wait "$QPID" 2>/dev/null
    QPID=""
}

await_line() { # Datei Text Sekunden
    local i
    for i in $(seq 1 $(( ${3:-20} * 5 ))); do
        [ -f "$1" ] && grep -qaF "$2" "$1" && return 0
        sleep 0.2
    done
    return 1
}

val() { sed -n "s/^nic: $2=\([0-9-]*\).*/\1/p" "$1" 2>/dev/null | tail -1; }

nzp_build() {
    local f
    for f in boot isr switch smp hv; do
        as --64 -o "$TMPD/$f.o" "kernel/arch/x86_64/$f.s" 2>"$TMPD/as.err" || return 1
    done
    as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || return 1
    "$FIRNC" kernel/kmain.fi -o "$TMPD/k0.o" >"$TMPD/e0" 2>&1 || {
        echo "--- firnc kmain.fi:" >&2; head -20 "$TMPD/e0" >&2; return 1; }
    "$FIRNC" kernel/uprog.fi -o "$TMPD/u0.o" >>"$TMPD/e0" 2>&1 || {
        echo "--- firnc uprog.fi:" >&2; head -20 "$TMPD/e0" >&2; return 1; }
    ld -n -T "$LDSCRIPT" \
        --defsym=KERNEL_MAIN="_F0.kernel_main" \
        --defsym=KERNEL_TRAP="_F0.trap__entry" \
        --defsym=KERNEL_SYSCALL="_F0.sys__entry" \
        --defsym=KERNEL_TASK_MAIN="_F0.tasks__main" \
        --defsym=KERNEL_USER_START="_F0.proc__user_start" \
        --defsym=KERNEL_AP_MAIN="_F0.smp__ap_main" \
        --defsym=USER_MAIN="_F0.u_enter" \
        -o "$TMPD/k0.elf" "$TMPD/boot.o" "$TMPD/isr.o" "$TMPD/switch.o" \
        "$TMPD/smp.o" "$TMPD/hv.o" "$TMPD/k0.o" "$TMPD/u0.o" 2>"$TMPD/ld0.err" || {
        echo "--- ld:" >&2; head -10 "$TMPD/ld0.err" >&2; return 1; }
    objcopy -O elf32-i386 "$TMPD/k0.elf" "$TMPD/k0.mb" 2>/dev/null || return 1
    gcc -O2 -o "$TMPD/bridge" tools/net/bridge.c 2>"$TMPD/gcc.err" || return 1
    return 0
}

# ------------------------------------------------- eine Durchsatzmessung
# durchsatz <Ausgabedatei> <Bytes> <Verzoegerung|""> <Verlust v1|""> <Verlust v0|"">
#
durchsatz() {
    local out=$1 bytes=$2 delay=${3:-} l1=${4:-} l0=${5:-} extra=${6:-}
    dd if=/dev/urandom of="$TMPD/payload.bin" bs=1024 count=$((bytes/1024)) 2>/dev/null
    wire_up "$l1" "$l0" "$delay"
    bridge_up
    qemu_bg "$TMPD/k0.mb" \
        "$NZP_BASE nic nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=1 nport=7 nbytes=$bytes $extra" "$out"
    if await_line "$out" "nic: listening=7" 40; then
        ip netns exec "$NS" timeout "${NZP_NC_TIMEOUT:-120}" nc -q 1 "$OSUM_IP" 7 \
            < "$TMPD/payload.bin" >/dev/null 2>&1
    fi
    qemu_wait
    bridge_down
    wire_down
}
