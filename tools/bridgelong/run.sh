#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
W=$(mktemp -d)
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

for t in qemu-system-x86_64 ip python3 gcc; do
    command -v "$t" >/dev/null 2>&1 || { echo "BRIDGELONG: skipped, $t missing"; exit 0; }
done

NS=blong-$$
V0=l0-$$
V1=lh1
QPORT=$(( 21000 + ($$ % 300) * 2 ))
BPORT=$(( QPORT + 1 ))
OSUM_IP=10.9.0.2
HOST_IP=10.9.0.1
WATCHDOG_S=30
COMMAND_S=${BRIDGELONG_COMMAND_S:-100}
RUN_S=${BRIDGELONG_RUN_S:-240}
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
BRIDGE_PROGS="sh ls cat echo chmod jsig jarvisctl sleep" bash tools/bridge/build.sh "$W" 0 >"$W/build.txt" 2>&1 || {
    echo "the build failed"; tail -5 "$W/build.txt"; exit 1; }
python3 tools/hwnet/mkcerts.py "$W/certs" jarvis.test >"$W/certs.txt" 2>&1 || {
    echo "mkcerts failed"; exit 1; }
cp "$W/certs/ca.pem" "$W/roots.pem"
printf 'nameserver %s\n' "$HOST_IP" > "$W/resolv.conf"
cat > "$W/permissions.conf" <<CONF
transport       = https
servername      = jarvis.test
path            = /bruecke/draht
roots           = /etc/ssl/roots.pem
watchdog        = $WATCHDOG_S
commands        = yes
command_allowed = /bin/sleep
command_timeout = 400
read            = /var/jarvis/
write           = /var/jarvis/
list            = /var/jarvis/
screenshot      = no
sysinfo         = yes
input           = no
max_output      = 65536
max_file        = 262144
log             = /var/log/jarvisd.log
work_file       = /var/jarvis/output.txt
permit_file     = /var/jarvis/screenshot-permit
CONF
SPEC="/bin/ /proc/ /dev/ /etc/ /etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/"
for p in sh ls cat echo chmod jsig jarvisctl sleep; do SPEC="$SPEC /bin/$p=$W/$p.elf"; done
SPEC="$SPEC /bin/jarvisd=$W/jarvisd.elf /etc/jarvis/permissions.conf=$W/permissions.conf"
SPEC="$SPEC /etc/ssl/roots.pem=$W/roots.pem /etc/resolv.conf=$W/resolv.conf"
bash tools/mkfsfi/mkfs.sh build "$W/probe.img" 16384 $SPEC >"$W/mkfs.txt" 2>&1 || {
    echo "mkfs failed"; tail -4 "$W/mkfs.txt"; exit 1; }
ok "kernel, programs and certificates are built"

echo "== 2. wire =="
gcc -O2 -o "$W/bridge" tools/net/bridge.c 2>"$W/gcc.txt" || { echo "bridge.c does not build"; exit 1; }
ip netns add "$NS" 2>/dev/null || { echo "BRIDGELONG: skipped, no network namespaces"; exit 0; }
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

: > "$W/peer.log"; rm -f "$W/stall"
ip netns exec "$NS" python3 tools/bridgerecon/fakebridge.py \
    --cert "$W/certs/good.pem" --key "$W/certs/good.key" \
    --bind "$HOST_IP" --log "$W/peer.log" --stall "$W/stall" \
    --job "/bin/sleep $COMMAND_S" >"$W/peer.out" 2>&1 & PEER=$!
for i in $(seq 1 20); do grep -q READY "$W/peer.log" && break; sleep 0.25; done

echo "== 3. a $COMMAND_S s command with watchdog = $WATCHDOG_S s =="
cp "$W/probe.img" "$W/live.img"
timeout $((RUN_S + 60)) qemu-system-x86_64 -kernel "$W/k.mb" -m 256 \
    -append "osum vfs nokbd nosched nofs noring3 gfx nocursor nic nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=0 nwait=0 script=jarvisd" \
    -serial "file:$W/serial.txt" -display none -no-reboot \
    -drive "file=$W/live.img,format=raw,if=ide,index=0" \
    -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
    -device e1000,netdev=n0,mac=52:54:00:cc:dd:ee -vga std \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$W/q.log" 2>&1 &
QPID=$!
for i in $(seq 1 $RUN_S); do
    grep -q '^DONE\|DONE ' "$W/peer.log" && break
    sleep 1
done
sleep 3
kill $QPID 2>/dev/null; wait $QPID 2>/dev/null

grep -aq 'supervisor started' "$W/serial.txt" && ok "the supervisor started" || bad "no supervisor"
grep -q 'ANSWER welcome' "$W/peer.log" && ok "the device signed in" || bad "the device never signed in"
grep -q 'JOB-SENT' "$W/peer.log" && ok "the long command was handed out" || bad "the command was never handed out"
if grep -aq 'WORKER-KILLED-SILENT\|worker silent too long' "$W/serial.txt"; then
    bad "the supervisor killed the worker during the command"
    grep -a 'WORKER-KILLED-SILENT\|worker silent' "$W/serial.txt" | head -3 | sed 's/^/        /'
else
    ok "no silent-worker kill during the command"
fi
grep -q 'DONE 1 ok' "$W/peer.log" && ok "the result of the long command arrived ($(grep 'DONE' "$W/peer.log" | head -1))" || bad "no result for the long command"
n=$(grep -c 'ANSWER welcome' "$W/peer.log")
[ "$n" = 1 ] && ok "one session for the whole command" || bad "$n sessions (want 1)"
echo
echo "BRIDGELONG: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
