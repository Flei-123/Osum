#!/usr/bin/env bash
# tools/feedback/dbg.sh -- EIN Lauf mit Netz, laut. Benutzt die
# Bauteile eines vorherigen `FBKEEP=1 run.sh`.
#   dbg.sh <TMPD> "<script>" [netz 0|1]
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$1; SKRIPT=$2; NETZ=${3:-1}
NS=fbd-$$; V0=fbd0-$$; V1=fbd1
OSUM_IP=10.9.0.2; HOST_IP=10.9.0.1
QPORT=$(( 14000 + ($$ % 400) * 2 )); BPORT=$(( QPORT + 1 )); SRVPORT=8443
ACCEL=(); [ -w /dev/kvm ] && ACCEL=(-accel kvm -cpu host)
BRPID=""; SRVPID=""
cleanup() { [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
            [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null
            ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null; }
trap cleanup EXIT
mkdir -p "$TMPD/dbgein"
if [ "$NETZ" = 1 ]; then
    ip netns add "$NS"
    ip link add "$V0" type veth peer name "$V1"
    ip link set "$V1" netns "$NS"
    ip netns exec "$NS" ip addr add "$HOST_IP/24" dev "$V1"
    ip netns exec "$NS" ip link set "$V1" up
    ip netns exec "$NS" ip link set lo up
    ip link set "$V0" up
    ethtool -K "$V0" tx off rx off tso off gso off gro off >/dev/null 2>&1
    ip netns exec "$NS" ethtool -K "$V1" tx off rx off tso off gso off gro off >/dev/null 2>&1
    "$TMPD/bridge" "$V0" "$BPORT" "$QPORT" 2>"$TMPD/dbg.br.log" & BRPID=$!
    ip netns exec "$NS" python3 tools/feedback/server.py \
        "$TMPD/certs/good.pem" "$TMPD/certs/good.key" "$SRVPORT" "$TMPD/dbgein" \
        > "$TMPD/dbg.srv.log" 2>&1 & SRVPID=$!
    sleep 1.2
    NET=(-netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT"
         -device "virtio-net-pci,netdev=n0,mac=52:54:00:fe:ed:ba")
else
    NET=()
fi
cp "$TMPD/disk.img" "$TMPD/dbg.img"
timeout 240 qemu-system-x86_64 "${ACCEL[@]}" -kernel "$TMPD/k.mb" -m 512 \
    -append "osum gfx nocursor nokbd nosched noproc nofs nic nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=0 nwait=0 script=$SKRIPT" \
    -serial "file:$TMPD/dbg.txt" -display none -no-reboot -vga std \
    "${NET[@]}" \
    -drive "file=$TMPD/dbg.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
echo "=== serial ==="
grep -av '^elf:' "$TMPD/dbg.txt" | sed -n '95,220p'
echo "=== bridge ==="; cat "$TMPD/dbg.br.log" 2>/dev/null
echo "=== server ==="; cat "$TMPD/dbg.srv.log" 2>/dev/null
echo "=== eingang ==="; ls -la "$TMPD/dbgein"
