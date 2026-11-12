#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
W=$(mktemp -d)
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

for t in qemu-system-x86_64 ip python3 gcc; do
    command -v "$t" >/dev/null 2>&1 || { echo "BRIDGERECON: skipped, $t missing"; exit 0; }
done

NS=brecon-$$
V0=r0-$$
V1=rh1
QPORT=$(( 21000 + ($$ % 300) * 2 ))
BPORT=$(( QPORT + 1 ))
OSUM_IP=10.9.0.2
HOST_IP=10.9.0.1
MAX_HOLD_S=20
STALL_S=45
BLACKHOLE_S=25
RECOVER_S=60
PEER=""
BRPID=""

cleanup() {
    [ -n "$PEER" ] && kill "$PEER" 2>/dev/null
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    pkill -f "qemu-system-x86_64.*$W" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    rm -rf "$W"
}
trap cleanup EXIT

echo "== 1. build =="
bash tools/bridge/build.sh "$W" 0 >"$W/build.txt" 2>&1 || {
    echo "the build failed"; tail -5 "$W/build.txt"; exit 1; }
python3 tools/hwnet/mkcerts.py "$W/certs" jarvis.test >"$W/certs.txt" 2>&1 || {
    echo "mkcerts failed"; exit 1; }
cp "$W/certs/ca.pem" "$W/roots.pem"
printf 'nameserver %s\n' "$HOST_IP" > "$W/resolv.conf"
cat > "$W/permissions.conf" <<CONF
transport     = https
servername    = jarvis.test
path          = /bruecke/draht
roots         = /etc/ssl/roots.pem
commands      = no
read          = /var/jarvis/
write         = /var/jarvis/
list          = /var/jarvis/
screenshot    = no
sysinfo       = yes
input         = no
max_output    = 65536
max_file      = 262144
log           = /var/log/jarvisd.log
work_file     = /var/jarvis/output.txt
permit_file   = /var/jarvis/screenshot-permit
CONF
SPEC="/bin/ /etc/ /etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/"
for p in sh ls cat echo chmod jsig jarvisctl; do SPEC="$SPEC /bin/$p=$W/$p.elf"; done
SPEC="$SPEC /bin/jarvisd=$W/jarvisd.elf /etc/jarvis/permissions.conf=$W/permissions.conf"
SPEC="$SPEC /etc/ssl/roots.pem=$W/roots.pem /etc/resolv.conf=$W/resolv.conf"
bash tools/mkfsfi/mkfs.sh build "$W/probe.img" 16384 $SPEC >"$W/mkfs.txt" 2>&1 || {
    echo "mkfs failed"; tail -4 "$W/mkfs.txt"; exit 1; }
ok "kernel, programs and certificates are built"

echo "== 2. wire =="
gcc -O2 -o "$W/bridge" tools/net/bridge.c 2>"$W/gcc.txt" || { echo "bridge.c does not build"; exit 1; }
ip netns add "$NS" 2>/dev/null || { echo "BRIDGERECON: skipped, no network namespaces"; exit 0; }
ip link add "$V0" type veth peer name "$V1"
ip link set "$V1" netns "$NS"
ip netns exec "$NS" ip addr add $HOST_IP/24 dev "$V1"
ip netns exec "$NS" ip link set "$V1" up
ip netns exec "$NS" ip link set lo up
ip link set "$V0" up
ethtool -K "$V0" tx off rx off tso off gso off gro off >/dev/null 2>&1
ip netns exec "$NS" ethtool -K "$V1" tx off rx off tso off gso off gro off >/dev/null 2>&1
"$W/bridge" "$V0" "$BPORT" "$QPORT" 2>"$W/br.log" & BRPID=$!
sleep 0.5

start_peer() {
    : > "$W/peer.log"; rm -f "$W/stall"
    ip netns exec "$NS" python3 tools/bridgerecon/fakebridge.py \
        --cert "$W/certs/good.pem" --key "$W/certs/good.key" \
        --bind "$HOST_IP" --log "$W/peer.log" --stall "$W/stall" \
        >"$W/peer.out" 2>&1 & PEER=$!
    for i in $(seq 1 20); do grep -q READY "$W/peer.log" && return 0; sleep 0.25; done
    return 1
}

start_guest() {
    local serial=$1 flags=$2 deadline=$3
    cp "$W/probe.img" "$W/live.img"
    timeout 300 qemu-system-x86_64 -kernel "$W/k.mb" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 gfx nocursor nic nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=0 nwait=0 script=jarvisd -v $flags -t $deadline;exit" \
        -serial "file:$serial" -display none -no-reboot \
        -drive "file=$W/live.img,format=raw,if=ide,index=0" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device e1000,netdev=n0,mac=52:54:00:cc:dd:ee -vga std \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$W/q.log" 2>&1 &
    QPID=$!
}

wait_welcome() {
    local want=$1 limit=$2
    for i in $(seq 1 $((limit * 2))); do
        [ "$(grep -c 'ANSWER welcome' "$W/peer.log")" -ge "$want" ] && return 0
        sleep 0.5
    done
    return 1
}

max_hold() {
    grep -a ' HOLD ' "$W/peer.log" | awk '{print $3}' | sort -n | tail -1
}

echo "== 3. current jarvisd: request that is never answered =="
start_peer || { echo "fake bridge did not start"; cat "$W/peer.out"; exit 1; }
start_guest "$W/s-new.txt" "" 290000
if wait_welcome 1 60; then ok "device signed in over https (DNS + TLS + wire)"; else bad "device never signed in"; tail -8 "$W/s-new.txt" | sed 's/^/        /'; fi
WELCOMES=$(grep -c 'ANSWER welcome' "$W/peer.log")
echo $(( $(date +%s) + STALL_S )) > "$W/stall"
note "server stops answering for $STALL_S s (requests stay open)"
sleep $((STALL_S + 5))
HOLD=$(max_hold)
if [ -n "${HOLD:-}" ] && awk "BEGIN{exit !($HOLD <= $MAX_HOLD_S + 2)}"; then
    ok "device gave up on the dead request after ${HOLD} s (limit $MAX_HOLD_S s)"
else
    bad "device held a dead request for ${HOLD:-none} s (limit $MAX_HOLD_S s)"
fi
if wait_welcome $((WELCOMES + 1)) $RECOVER_S; then
    ok "device signed in again within $RECOVER_S s after the stall"
else
    bad "device did not sign in again within $RECOVER_S s"
fi

echo "== 4. current jarvisd: link black hole =="
WELCOMES=$(grep -c 'ANSWER welcome' "$W/peer.log")
ip netns exec "$NS" ip link set "$V1" down
note "link down for $BLACKHOLE_S s"
sleep $BLACKHOLE_S
ip netns exec "$NS" ip link set "$V1" up
if wait_welcome $((WELCOMES + 1)) $RECOVER_S; then
    ok "device came back within $RECOVER_S s after the link returned"
else
    bad "device did not come back within $RECOVER_S s after the link returned"
fi
kill $QPID 2>/dev/null; wait $QPID 2>/dev/null
if grep -aq 'net recovered' "$W/s-new.txt"; then
    ok "log line for the reconnect is written"
    grep -a ' net ' "$W/s-new.txt" | head -6 | sed 's/^/        /'
else
    bad "no reconnect log line"
fi
kill "$PEER" 2>/dev/null; PEER=""; sleep 0.5

echo "== 5. counter-proof: old behaviour (-o) =="
start_peer || { echo "fake bridge did not start"; exit 1; }
start_guest "$W/s-old.txt" "-o" 150000
wait_welcome 1 60 || bad "old device never signed in"
echo $(( $(date +%s) + STALL_S )) > "$W/stall"
sleep 80
HOLD=$(max_hold)
if [ -n "${HOLD:-}" ] && awk "BEGIN{exit !($HOLD > $MAX_HOLD_S + 2)}"; then
    ok "old behaviour is detected: dead request held ${HOLD} s"
else
    bad "counter-proof is not red: held ${HOLD:-none} s"
fi
kill $QPID 2>/dev/null; wait $QPID 2>/dev/null

echo
echo "BRIDGERECON: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
