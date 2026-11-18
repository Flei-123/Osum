#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
W=$(mktemp -d)
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

for t in qemu-system-x86_64 ip python3 gcc; do
    command -v "$t" >/dev/null 2>&1 || { echo "BEAT: skipped, $t missing"; exit 0; }
done

NS=beat-$$
V0=b0-$$
V1=bh1
QPORT=$(( 22000 + ($$ % 300) * 2 ))
BPORT=$(( QPORT + 1 ))
OSUM_IP=10.9.1.2
HOST_IP=10.9.1.1
FREEZE_S=${BEAT_FREEZE_S:-60}
RUN_S=${BEAT_RUN_S:-100}
MAX_GAP_S=${BEAT_MAX_GAP_S:-25}
LOAD=${BEAT_LOAD:-0}
SMP=${BEAT_SMP:-1}
THROTTLE=${BEAT_THROTTLE:-4194304}
EXTRA=${BEAT_KARGS:-}
PEER=""
BRPID=""
QPID=""

cleanup() {
    [ -n "$PEER" ] && kill "$PEER" 2>/dev/null
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    [ -n "$QPID" ] && kill "$QPID" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    [ -n "${BEAT_KEEP:-}" ] && cp -r "$W" "$BEAT_KEEP" 2>/dev/null
    rm -rf "$W"
}
trap cleanup EXIT

echo "== 1. build =="
B=${BEAT_BUILD:-$W/b}
if [ -z "${BEAT_BUILD:-}" ]; then
    bash tools/bridge/build.sh "$B" 0 >"$W/build.txt" 2>&1 || {
        echo "the build failed"; tail -5 "$W/build.txt"; exit 1; }
fi
python3 tools/hwnet/mkcerts.py "$W/certs" jarvis.test >"$W/certs.txt" 2>&1 || {
    echo "mkcerts failed"; exit 1; }
cp "$W/certs/ca.pem" "$W/roots.pem"
printf 'nameserver %s\n' "$HOST_IP" > "$W/resolv.conf"
cat > "$W/permissions.conf" <<CONF
transport     = https
servername    = jarvis.test
path          = /bruecke/draht
roots         = /etc/ssl/roots.pem
commands      = yes
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
head -c 25165824 /dev/urandom > "$W/big.bin"
loadscript() {
    local out=$1 body=$2 n=$3
    : > "$out"
    for i in $(seq 1 "$n"); do echo "$body" >> "$out"; done
}
loadscript "$W/r1.sh" "shasum /t/big.bin" 60
loadscript "$W/r2.sh" "shasum /t/big.bin" 60
loadscript "$W/w1.sh" "cat /t/big.bin > /var/jarvis/w1.bin" 60
loadscript "$W/x1.sh" "ls /bin" 400
ok "kernel, programs and certificates are built"

echo "== 2. wire =="
gcc -O2 -o "$W/bridge" tools/net/bridge.c 2>"$W/gcc.txt" || { echo "bridge.c does not build"; exit 1; }
ip netns add "$NS" 2>/dev/null || { echo "BEAT: skipped, no network namespaces"; exit 0; }
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
    : > "$W/peer.log"
    ip netns exec "$NS" python3 tools/bridgerecon/fakebridge.py \
        --cert "$W/certs/good.pem" --key "$W/certs/good.key" \
        --bind "$HOST_IP" --log "$W/peer.log" --stall "$W/stall" \
        >"$W/peer.out" 2>&1 & PEER=$!
    for i in $(seq 1 20); do grep -q READY "$W/peer.log" && return 0; sleep 0.25; done
    return 1
}

run_guest() {
    local label=$1 flags=$2
    {
        echo "jarvisd -v $flags -t $((RUN_S * 1000)) &"
        if [ "$LOAD" = 1 ]; then
            echo "sh /t/r1.sh &"
            echo "sh /t/r2.sh &"
            echo "sh /t/w1.sh &"
            echo "sh /t/x1.sh &"
        fi
        echo "sleep $((RUN_S + 5))"
        echo "exit"
    } > "$W/g.sh"
    SPEC=$(cat "$B/spec.txt")
    SPEC="$SPEC /t/ /t/big.bin=$W/big.bin /t/g.sh=$W/g.sh /t/r1.sh=$W/r1.sh /t/r2.sh=$W/r2.sh /t/w1.sh=$W/w1.sh /t/x1.sh=$W/x1.sh"
    SPEC="$SPEC /etc/jarvis/permissions.conf=$W/permissions.conf /etc/ssl/roots.pem=$W/roots.pem /etc/resolv.conf=$W/resolv.conf"
    bash tools/mkfsfi/mkfs.sh build "$W/probe.img" 131072 $SPEC >"$W/mkfs.txt" 2>&1 || {
        echo "mkfs failed"; tail -4 "$W/mkfs.txt"; exit 1; }
    start_peer || { echo "fake bridge did not start"; exit 1; }
    timeout $((RUN_S + 120)) qemu-system-x86_64 -kernel "$B/k.mb" -m 512 -smp "$SMP" \
        -append "osum nokbd nosched noproc nofs noring3 gfx nocursor nic nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=0 nwait=0 $EXTRA script=sh /t/g.sh;exit" \
        -serial "file:$W/serial-$label.txt" -display none -no-reboot \
        -drive "file=$W/probe.img,format=raw,if=ide,index=0,throttling.bps-total=$THROTTLE" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device e1000,netdev=n0,mac=52:54:00:cc:dd:ee -vga std \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$W/q.log" 2>&1 &
    QPID=$!
    sleep $((RUN_S + 8))
    kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null; QPID=""
    kill "$PEER" 2>/dev/null; wait "$PEER" 2>/dev/null; PEER=""
    cp "$W/peer.log" "$W/peer-$label.log"
}

gap_of() {
    grep -a ' REQ ' "$W/peer-$1.log" | awk '{t=$1; if (p>0 && t-p>m) m=t-p; p=t} END{printf "%.1f", m+0}'
}

echo "== 3. main loop frozen for $FREEZE_S s, heartbeat process on =="
run_guest beat "-F $FREEZE_S"
GAP=$(gap_of beat)
ALIVES=$(grep -ac ' REQ alive' "$W/peer-beat.log")
note "alive requests $ALIVES, longest gap ${GAP} s"
[ "$ALIVES" -ge 3 ] && ok "heartbeat process sent $ALIVES alive requests during the freeze" || bad "only $ALIVES alive requests"
awk "BEGIN{exit !($GAP <= $MAX_GAP_S)}" && ok "longest gap ${GAP} s <= ${MAX_GAP_S} s while the main loop was frozen" || bad "gap ${GAP} s > ${MAX_GAP_S} s"

echo "== 4. counter-proof: heartbeat process off (-B) =="
run_guest nobeat "-F $FREEZE_S -B"
GAP0=$(gap_of nobeat)
note "longest gap ${GAP0} s"
awk "BEGIN{exit !($GAP0 > $MAX_GAP_S)}" && ok "counter-proof is red: gap ${GAP0} s without the heartbeat process" || bad "counter-proof is not red: gap ${GAP0} s"

echo
echo "BEAT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
