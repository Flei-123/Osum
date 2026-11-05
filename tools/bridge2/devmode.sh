#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
W=${DEVMODE_KEEP:-$(mktemp -d)}
mkdir -p "$W"
NS=devmode-$$
V0=dm0-$$
V1=dh1
QPORT=$(( 17000 + ($$ % 400) * 2 ))
BPORT=$(( QPORT + 1 ))
OSUM_IP=10.9.0.2
HOST_IP=10.9.0.1
SRVPORT=8443
BRPID=""
SRVPID=""
cleanup() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    [ -n "${DEVMODE_KEEP:-}" ] || rm -rf "$W"
}
trap cleanup EXIT

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has()  { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnt(){ grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }

for t in qemu-system-x86_64 ip openssl python3 gcc; do
    command -v "$t" >/dev/null 2>&1 || { echo "DEVMODE: skipped, $t missing"; exit 0; }
done
python3 -c 'import cryptography' 2>/dev/null || { echo "DEVMODE: skipped, python3-cryptography missing"; exit 0; }
ip netns add "$NS" 2>/dev/null || { echo "DEVMODE: skipped, no network namespaces"; exit 0; }
ip netns del "$NS" 2>/dev/null
[ -w /dev/kvm ] && ACC=(-accel kvm -cpu host) || ACC=()

echo "== 1. config files =="
python3 - assets/jarvis/rechte-hp-dev.conf assets/jarvis/rechte-hp.conf assets/jarvis/rechte.conf <<'PY' && ok "every key of the three files is parsed by jarvisd" || bad "unknown keys (see above)"
import re, subprocess, sys
src = subprocess.check_output(["bash", "tools/structure/srcview.sh", "kernel/app/jarvisd.fi"]).decode("latin-1")
keys = set(re.findall(r'var s_\w+: \[u8; \d+\] = "(\w+)\\0', src))
bad = []
for f in sys.argv[1:]:
    for l in open(f, encoding="utf-8"):
        m = re.match(r'^(\w+)\s*=', l)
        if m and m.group(1) not in keys:
            bad.append(f + ":" + m.group(1))
if bad:
    print("unknown keys:", ",".join(bad)); sys.exit(1)
PY
grep -Eq '^devmode[[:space:]]*=[[:space:]]*yes' assets/jarvis/rechte-hp-dev.conf && ok "dev config has devmode = yes" || bad "dev config lacks devmode = yes"
grep -Eq '^screenshot[[:space:]]*=[[:space:]]*always' assets/jarvis/rechte-hp-dev.conf && ok "dev config has screenshot = always" || bad "dev config lacks screenshot = always"
grep -Eq '^[[:space:]]*devmode' assets/jarvis/rechte-hp.conf assets/jarvis/rechte.conf && bad "COUNTER-PROOF: devmode in a normal config" || ok "normal configs (HP, default) carry no devmode"
grep -q 'IMAGE_PROFILE" = public \] && grep -Eq .*devmode' tools/usbimg/build.sh && ok "build.sh refuses devmode / screenshot=always in the public profile" || bad "no public guard for devmode in build.sh"
grep -q 'HP_DEV' tools/ota/republish-hp.sh && grep -q 'rechte-hp-dev.conf' tools/ota/republish-hp.sh && ok "republish-hp.sh switches to the dev config only with HP_DEV" || bad "republish-hp.sh lacks HP_DEV"
[ -f docs/DEVMODE.md ] && ok "docs/DEVMODE.md exists" || bad "docs/DEVMODE.md missing"

echo "== 2. build =="
bash vendor/firn/fetch-firnc.sh > "$W/fetch.log" 2>&1
bash tools/bridge/build.sh "$W/w0" 0 > "$W/b0.txt" 2>&1 && ok "kernel + jarvisd + jarvisctl + jsig build" || { bad "bridge build"; tail -8 "$W/b0.txt"; echo "DEVMODE: $pass passed, $fail failed"; exit 1; }
K="$W/w0/k.mb"
python3 tools/hwnet/mkcerts.py "$W/certs" jarvis.test > "$W/certs.txt" 2>&1 && ok "test certificates" || { bad "mkcerts"; cat "$W/certs.txt"; exit 1; }
gcc -O2 -o "$W/bridge" tools/net/bridge.c 2>/dev/null || { bad "bridge.c does not build"; exit 1; }

mkconf() {
    local f=$1; shift
    cat > "$f" <<CONF
server          = $HOST_IP:$SRVPORT
servername      = jarvis.test
roots           = /etc/ssl/roots.pem
commands        = yes
command_allowed = /bin/echo
command_allowed = /bin/jarvisctl
read            = /var/jarvis/
write           = /var/jarvis/
list            = /var/jarvis/
max_output      = 4096
max_file        = 8192
log             = /var/log/jarvisd.log
work_file       = /var/jarvis/output.txt
CONF
    for z in "$@"; do echo "$z" >> "$f"; done
}
mkconf "$W/dev.conf" "devmode = yes"
mkconf "$W/plain.conf"
echo "root:SECRET-HASH:0" > "$W/shadow"
echo "1" > "$W/stop"

image() {
    local img=$1 conf=$2; shift 2
    bash tools/mkfsfi/mkfs.sh build "$img" 16384 \
        /bin/ /etc/ /etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/ /tmp/ \
        "/bin/sh=$W/w0/sh.elf" "/bin/ls=$W/w0/ls.elf" "/bin/cat=$W/w0/cat.elf" \
        "/bin/echo=$W/w0/echo.elf" "/bin/chmod=$W/w0/chmod.elf" "/bin/jsig=$W/w0/jsig.elf" \
        "/bin/jarvisctl=$W/w0/jarvisctl.elf" "/bin/jarvisd=$W/w0/jarvisd.elf" \
        "/etc/jarvis/permissions.conf=$conf" "/etc/ssl/roots.pem=$W/certs/ca.pem" \
        "/etc/shadow=$W/shadow" "$@" > "$W/mkfs.txt" 2>&1 \
        || { bad "mkfs for $img"; tail -4 "$W/mkfs.txt"; }
}
image "$W/dev.img" "$W/dev.conf"
image "$W/plain.img" "$W/plain.conf"
image "$W/stopped.img" "$W/dev.conf" "/var/jarvis/dev-off=$W/stop"

wire_up() {
    ip netns add "$NS"
    ip link add "$V0" type veth peer name "$V1"
    ip link set "$V1" netns "$NS"
    ip netns exec "$NS" ip addr add $HOST_IP/24 dev "$V1"
    ip netns exec "$NS" ip link set "$V1" up
    ip netns exec "$NS" ip link set lo up
    ip link set "$V0" up
    ethtool -K "$V0" tx off rx off tso off gso off gro off >/dev/null 2>&1
    ip netns exec "$NS" ethtool -K "$V1" tx off rx off tso off gso off gro off >/dev/null 2>&1
    "$W/bridge" "$V0" "$BPORT" "$QPORT" 2>"$W/br.log" & BRPID=$!
    sleep 0.4
}
wire_down() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null; BRPID=""
    ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null
}
peer_up() {
    ip netns exec "$NS" python3 tools/bridge/peer.py \
        --cert "$W/certs/good.pem" --key "$W/certs/good.key" \
        --port "$SRVPORT" --auftraege "$1" --aus "$2" --wartezeit 90 > "$2.stderr" 2>&1 & SRVPID=$!
    sleep 0.8
}
peer_down() { [ -n "$SRVPID" ] && { wait "$SRVPID" 2>/dev/null; SRVPID=""; }; }
vm_run() {
    local copy="$W/live-$RANDOM.img"
    cp "$1" "$copy"
    timeout 220 qemu-system-x86_64 "${ACC[@]}" -kernel "$K" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 nic nip=$OSUM_IP/24 ngw=$HOST_IP nsvc=0 nwait=0 script=$2" \
        -serial "file:$3" -display none -no-reboot \
        -drive "file=$copy,format=raw,if=ide,index=0" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "e1000,netdev=n0,mac=52:54:00:aa:bb:cc" -vga std \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    rm -f "$copy"
}
run_case() { # <name> <image> <jobs file> <script>
    wire_up
    peer_up "$3" "$W/g-$1.log"
    vm_run "$2" "$4" "$W/s-$1.txt"
    peer_down
    wire_down
}
status() { grep -a "^ANSWER $2 \|^ANTWORT $2 " "$W/g-$1.log" | head -1 | awk '{print $4}'; }
body()   { cat "$W/g-$1.log.$2.bin" 2>/dev/null; }
expect() { # <case> <nr> <status> <text>
    local got; got=$(status "$1" "$2")
    [ "$got" = "$3" ] && ok "$4" || bad "$4 -- status '$got', wanted '$3': $(body "$1" "$2" | head -c 120)"
}
HEX_ONE=31
HEX_HELLO=$(printf 'hello dev' | od -An -tx1 | tr -d ' \n')
HEX_NOSERVER=$(printf 'devmode = yes\n' | od -An -tx1 | tr -d ' \n')

cat > "$W/jobs-main.txt" <<AUF
lies|/etc/jarvis/permissions.conf|
lies|/etc/shadow|
lies|/etc/jarvis/device.key|
schreib|/var/jarvis/dev-off|$HEX_ONE
schreib|/tmp/hello.txt|$HEX_HELLO
lies|/tmp/hello.txt|
befehl|/bin/cat /etc/shadow|
befehl|/bin/ls /etc|
befehl|/bin/jsig|
befehl|/bin/cat /var/log/jarvisd.log|
befehl|/bin/echo hi > /var/log/jarvisd.log|
lies|/var/jarvis/devmode-active|
befehl|/bin/jarvisctl dev|
schreib|/etc/jarvis/permissions.conf|$HEX_NOSERVER
lies|/etc/jarvis/permissions.conf|
AUF
SCRIPT_MAIN="jsig init;jarvisd -1 -t 60000;jarvisctl dev;ls /var/jarvis;jarvisctl log 60;exit"

echo "== 3. dev mode ON: everything except key material =="
run_case main "$W/dev.img" "$W/jobs-main.txt" "$SCRIPT_MAIN"
F="$W/s-main.txt"
expect main 1 ok "read outside the read list (permissions.conf) is allowed"
expect main 2 nein "read /etc/shadow is refused"
expect main 3 nein "read /etc/jarvis/device.key is refused"
expect main 4 nein "write /var/jarvis/dev-off is refused (the stop marker is not writable remotely)"
expect main 5 ok "write outside the write list (/tmp) is allowed"
expect main 6 ok "and reads back"
[ "$(body main 6)" = "hello dev" ] && ok "read back octet for octet" || bad "read back differs: '$(body main 6)'"
expect main 7 nein "run cat /etc/shadow is refused"
expect main 8 ok "run /bin/ls outside command_allowed is allowed"
has "$W/g-main.log.8.bin" "shadow" "ls output came back"
expect main 9 nein "run /bin/jsig is refused (signing tool)"
expect main 10 ok "read-only program on the audit log is allowed"
expect main 11 nein "write to the audit log by redirect is refused"
expect main 12 ok "the active marker is readable"
expect main 13 ok "run jarvisctl dev"
has "$W/g-main.log.13.bin" "Dev mode: ACTIVE" "jarvisctl dev says ACTIVE through the bridge"
expect main 14 nein "writing a permissions.conf without server is refused"
expect main 15 ok "permissions.conf can be read after the refused write"
has "$W/g-main.log.15.bin" "servername" "the previous permissions.conf was restored (server line still there)"
has "$F" "Dev mode: ACTIVE" "device side: jarvisctl dev shows ACTIVE"
has "$F" "devmode-active" "marker file exists in /var/jarvis"
has "$F" "ok-dev" "audit log labels allowed jobs ok-dev"
has "$F" "REJECTED-dev" "audit log labels refused jobs REJECTED-dev"
has "$F" "devmode" "audit log has the dev-mode transition"
hasnt "$F" "SECRET-HASH" "no key material or shadow content on the device console"
hasnt "$W/g-main.log.2.bin" "SECRET-HASH" "shadow content never went over the wire"
[ "$(wc -c < "$W/g-main.log.3.bin")" -lt 200 ] && ok "device key: only a refusal text came back" || bad "device key: answer too long for a refusal"

echo "== 4. COUNTER-PROOF: same jobs, devmode off =="
sed "s#^schreib|/var/jarvis/dev-off|.*#lies|/etc/shadow|#" "$W/jobs-main.txt" > "$W/jobs-plain.txt"
run_case plain "$W/plain.img" "$W/jobs-plain.txt" "$SCRIPT_MAIN"
F="$W/s-plain.txt"
expect plain 1 nein "outside the read list is refused again"
expect plain 5 nein "outside the write list is refused again"
expect plain 8 nein "ls outside command_allowed is refused again"
expect plain 10 nein "cat outside command_allowed is refused again"
expect plain 13 ok "jarvisctl is allowed in this config"
has "$W/g-plain.log.13.bin" "not enabled" "jarvisctl dev says: not enabled in permissions.conf"
hasnt "$F" "ok-dev" "no ok-dev labels without devmode"
hasnt "$F" "devmode-active" "no active marker without devmode"
hasnt "$F" "Dev mode: ACTIVE" "never ACTIVE without devmode"

echo "== 5. EMERGENCY STOP from the bridge and the device =="
cat > "$W/jobs-stop.txt" <<AUF
lies|/etc/jarvis/permissions.conf|
befehl|/bin/jarvisctl dev off|
lies|/etc/jarvis/permissions.conf|
befehl|/bin/jarvisctl dev on|
lies|/etc/jarvis/permissions.conf|
AUF
run_case stop "$W/dev.img" "$W/jobs-stop.txt" "jsig init;jarvisd -1 -t 60000;jarvisctl dev;ls /var/jarvis;jarvisctl dev on;jarvisctl dev;ls /var/jarvis;exit"
F="$W/s-stop.txt"
expect stop 1 ok "before the stop: dev read works"
expect stop 2 ok "jarvisctl dev off runs through the bridge"
has "$W/g-stop.log.2.bin" "Dev mode: OFF" "it reports the emergency stop"
expect stop 3 nein "COUNTER-PROOF: the next job is refused after the stop"
expect stop 4 ok "jarvisctl dev on runs through the bridge"
has "$W/g-stop.log.4.bin" "Refused" "but the release through the bridge is refused"
expect stop 5 nein "the stop still holds after the release attempt"
has "$F" "emergency stop engaged" "device: status shows the engaged stop"
has "$F" "stop released" "device: dev on at the device releases it"

echo "== 6. stop marker present at boot =="
cat > "$W/jobs-boot.txt" <<AUF
lies|/etc/jarvis/permissions.conf|
befehl|/bin/cat /var/log/jarvisd.log|
AUF
run_case boot "$W/stopped.img" "$W/jobs-boot.txt" "jsig init;jarvisd -1 -t 60000;jarvisctl dev;exit"
expect boot 1 nein "dev config + stop marker = not active, job refused"
expect boot 2 nein "command outside the list refused"
has "$W/s-boot.txt" "emergency stop engaged" "status shows the engaged stop"

echo; echo "DEVMODE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
