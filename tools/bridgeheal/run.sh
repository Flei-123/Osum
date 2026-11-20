#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
W=$(mktemp -d)
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

for t in qemu-system-x86_64 ip python3 gcc; do
    command -v "$t" >/dev/null 2>&1 || { echo "BRIDGEHEAL: skipped, $t missing"; exit 0; }
done

NS=bheal-$$
V0=h0-$$
V1=hh1
QPORT=$(( 21000 + ($$ % 300) * 2 ))
BPORT=$(( QPORT + 1 ))
OSUM_IP=10.9.0.2
HOST_IP=10.9.0.1
MAX_HOLD_S=20
STALL_S=45
BLACKHOLE_S=25
RECOVER_S=60
HOG_PORT=7001
HOG_COUNT=8
HOG_PEER=""
PEER=""
BRPID=""

cleanup() {
    [ -n "$PEER" ] && kill "$PEER" 2>/dev/null
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    [ -n "$HOG_PEER" ] && kill "$HOG_PEER" 2>/dev/null
    pkill -f "qemu-system-x86_64.*$W" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    rm -rf "$W"
}
trap cleanup EXIT

echo "== 1. build =="
BRIDGE_PROGS="sh ls cat echo chmod jsig jarvisctl tcphog" bash tools/bridge/build.sh "$W" 0 >"$W/build.txt" 2>&1 || {
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
for p in sh ls cat echo chmod jsig jarvisctl tcphog; do SPEC="$SPEC /bin/$p=$W/$p.elf"; done
SPEC="$SPEC /bin/jarvisd=$W/jarvisd.elf /etc/jarvis/permissions.conf=$W/permissions.conf"
SPEC="$SPEC /etc/ssl/roots.pem=$W/roots.pem /etc/resolv.conf=$W/resolv.conf"
bash tools/mkfsfi/mkfs.sh build "$W/probe.img" 16384 $SPEC >"$W/mkfs.txt" 2>&1 || {
    echo "mkfs failed"; tail -4 "$W/mkfs.txt"; exit 1; }
ok "kernel, programs and certificates are built"

echo "== 2. wire =="
gcc -O2 -o "$W/bridge" tools/net/bridge.c 2>"$W/gcc.txt" || { echo "bridge.c does not build"; exit 1; }
ip netns add "$NS" 2>/dev/null || { echo "BRIDGEHEAL: skipped, no network namespaces"; exit 0; }
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
        -append "osum nokbd nosched noproc nofs noring3 gfx nocursor nic nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=0 nwait=0 $flags script=tcphog $HOST_IP $HOG_PORT $HOG_COUNT;jarvisd -v -t $deadline;exit" \
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

ip netns exec "$NS" python3 tools/tcporphan/peer.py silent "$HOG_PORT" >"$W/hog-peer.out" 2>&1 & HOG_PEER=$!
sleep 0.5

echo "== 3. bridge keeps a TCP slot while other programs fill the table =="
start_peer || { echo "fake bridge did not start"; cat "$W/peer.out"; exit 1; }
start_guest "$W/s-new.txt" "" 150000
if wait_welcome 1 90; then ok "device signed in although a program tried to take all $HOG_COUNT slots"; else bad "device never signed in"; fi
L=$(grep -a '^TCPHOG' "$W/s-new.txt" | head -1)
if echo "$L" | grep -q "held=$((HOG_COUNT - 1)) "; then ok "the hog got $((HOG_COUNT - 1)) slots, one stayed free ($L)"; else bad "hog result unexpected ($L)"; fi
grep -aq 'inet: tcp slot kept for the bridge' "$W/s-new.txt" && ok "kernel logs the refused connection" || bad "no kernel log for the refused connection"
kill $QPID 2>/dev/null; wait $QPID 2>/dev/null
kill "$PEER" 2>/dev/null; PEER=""; sleep 0.5

echo "== 4. counter-proof: nobridgeslot =="
start_peer || { echo "fake bridge did not start"; exit 1; }
start_guest "$W/s-old.txt" "nobridgeslot" 100000
sleep 75
L=$(grep -a '^TCPHOG' "$W/s-old.txt" | head -1)
if echo "$L" | grep -q "held=$HOG_COUNT "; then ok "counter-proof: the hog takes every slot ($L)"; else bad "counter-proof: hog result unexpected ($L)"; fi
if [ "$(grep -c 'ANSWER welcome' "$W/peer.log")" -eq 0 ]; then ok "counter-proof: device never signs in"; else bad "counter-proof is not red: device signed in"; fi
if grep -a ' net ' "$W/s-old.txt" | grep -aq 'tcp='; then ok "net log lines carry the TCP table state"; grep -a ' net ' "$W/s-old.txt" | head -3 | sed 's/^/        /'; else bad "net log lines lack tcp="; fi
kill $QPID 2>/dev/null; wait $QPID 2>/dev/null

echo
echo "BRIDGEHEAL: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
