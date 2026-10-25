#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/smb/guest.sh -- smbctl inside the OrientOS guest (QEMU, e1000) against Samba in a netns.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

NIC=${HWNET_NIC:-e1000}
NS=smbg-$$
V0=sg0-$$
V1=sg1
QPORT=$(( 14000 + ($$ % 400) * 2 ))
BPORT=$(( QPORT + 1 ))
TMPD=$(mktemp -d)
chmod 755 "$TMPD"
BRPID=""
. tools/smb/samba.sh
cleanup() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    samba_stop
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    rm -rf "$TMPD"
}
trap cleanup EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' is missing"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' is present" || ok "$3"; }

for t in qemu-system-x86_64 ip smbd smbpasswd gcc sha256sum; do
    command -v "$t" >/dev/null 2>&1 || command -v "/usr/sbin/$t" >/dev/null 2>&1 || { echo "SMBGUEST: skipped, $t is missing"; exit 0; }
done
export PATH="$PATH:/usr/sbin"
ip netns add "$NS" 2>/dev/null || { echo "SMBGUEST: skipped, no network namespaces"; exit 0; }
ip netns del "$NS" 2>/dev/null

echo "== 1. build: smbctl as a ring-3 app, kernel, image =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
if FIRNLIB="$ROOT/lib" vendor/firn/bin/firnc -c --profile=app -o "$TMPD/smbctl.o" kernel/app/smbctl.fi > "$TMPD/cc.log" 2>&1; then
    ok "firnc --profile=app: smbctl.fi"
else
    bad "smbctl.fi does not compile"; head -10 "$TMPD/cc.log"; echo "SMBGUEST: $pass passed, $fail failed"; exit 1
fi
undef=$(nm -u "$TMPD/smbctl.o" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
[ -z "$undef" ] && ok "no undefined symbol" || bad "undefined: $undef"
ld -T kernel/user/user.ld -o "$TMPD/smbctl.elf" "$TMPD/smbctl.o" 2>"$TMPD/ld.err" && ok "ld with kernel/user/user.ld" || { bad "ld failed"; head -3 "$TMPD/ld.err"; }
strip --strip-all "$TMPD/smbctl.elf" 2>/dev/null
bash tools/hwnet/build.sh "$TMPD/s0" 0 > "$TMPD/b0.txt" 2>&1 || { bad "the kernel does not build"; echo "SMBGUEST: $pass passed, $fail failed"; exit 1; }
K="$TMPD/s0/k.mb"
gcc -O2 -o "$TMPD/bridge" tools/net/bridge.c 2>/dev/null || bad "bridge.c"
head -c 40000 /dev/urandom > "$TMPD/up.bin"
python3 tools/osum/mkfs.py build "$TMPD/disk.raw" 16384 /bin/ \
    "/bin/sh=$TMPD/s0/sh.elf" "/bin/smbctl=$TMPD/smbctl.elf" "/up.bin=$TMPD/up.bin" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "image with /bin/sh, /bin/smbctl and a 40000-octet file" || bad "mkfs failed"

samba_setup "$TMPD/smb" 445
SMB_PREFIX="ip netns exec $NS"
SMB_BIND=10.9.0.1

wire_up() {
    ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null
    ip netns add "$NS"
    ip link add "$V0" type veth peer name "$V1"
    ip link set "$V1" netns "$NS"
    ip netns exec "$NS" ip addr add 10.9.0.1/24 dev "$V1"
    ip netns exec "$NS" ip link set "$V1" up
    ip netns exec "$NS" ip link set lo up
    ip link set "$V0" up
    ethtool -K "$V0" tx off rx off tso off gso off gro off >/dev/null 2>&1
    ip netns exec "$NS" ethtool -K "$V1" tx off rx off tso off gso off gro off >/dev/null 2>&1
    "$TMPD/bridge" "$V0" "$BPORT" "$QPORT" 2>"$TMPD/br.log" & BRPID=$!
    sleep 0.4
}
wire_down() {
    samba_stop
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null; BRPID=""
    ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null
}
run_osum() { # <script> <out>
    cp "$TMPD/disk.raw" "$TMPD/run.raw"
    timeout 240 qemu-system-x86_64 -kernel "$K" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 nic nip=10.9.0.2/24 ngw=10.9.0.1 nsvc=0 nwait=0 script=$1;exit" \
        -serial "file:$2" -display none -no-reboot \
        -drive "file=$TMPD/run.raw,format=raw,if=ide,index=0" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "$NIC,netdev=n0,mac=52:54:00:aa:bb:cc" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}
digest_of() { grep -aoE "smbctl: $2 octets $3 sha256 [0-9a-f]+" "$1" | tail -1 | awk '{print $NF}'; }

S="smbctl -u gateuser 10.9.0.1"
run_case() { # <name> <signing> <script> ; expects SMB_MIN/SMB_MAX in the environment
    wire_up
    samba_setup_user_once
    samba_start "$2" || { bad "$1: samba did not start"; head -3 "$TMPD/smb/smbd.out"; }
    run_osum "$3" "$TMPD/$1.txt"
    [ -n "${SMB_KEEP:-}" ] && cp "$TMPD/$1.txt" "$SMB_KEEP/"
    wire_down
}
samba_setup_user_once() { samba_conf auto; samba_user; }

WANT_BIG=$(sha256sum "$TMPD/smb/share/big.bin" | awk '{print $1}')
WANT_UP=$(sha256sum "$TMPD/up.bin" | awk '{print $1}')

echo "== 2. signing auto: ls, get, put, and the refusals =="
run_case auto auto "SMB_PASSWORD=gatepass;export SMB_PASSWORD;$S data ls;$S data get big.bin /big.bin;$S data put /up.bin guest-up.bin;$S data put /big.bin rt-big.bin;$S -w x data ls;$S data get hello.txt;SMB_PASSWORD=wrongpass;$S data ls;SMB_PASSWORD=gatepass;$S nosuchshare ls;$S data get nothere.txt"
A="$TMPD/auto.txt"
has "$A" "hello.txt" "ls lists hello.txt from inside the guest"
has "$A" "smbctl: ls ok" "ls ok"
has "$A" "dialect 0311" "the guest negotiated SMB 3.1.1 (preauth hash, SMBSigningKey) with Samba"
[ "$(digest_of "$A" get 300000)" = "$WANT_BIG" ] && ok "get big.bin: 300000 octets, sha256 equals the share's file" || bad "get big.bin digest '$(digest_of "$A" get 300000)' != $WANT_BIG"
[ -f "$SHARE/guest-up.bin" ] && [ "$(sha256sum "$SHARE/guest-up.bin" | awk '{print $1}')" = "$WANT_UP" ] && ok "put: 40000 octets landed on the share byte-exact" || bad "put: file on the share missing or different"
[ -f "$SHARE/rt-big.bin" ] && cmp -s "$SHARE/rt-big.bin" "$SHARE/big.bin" && ok "get then put of 300000 octets (several chunks) round-trips byte-exact" || bad "round trip of big.bin"
has "$A" "unknown option" "counter-proof: -w (password in argv) is rejected"
has "$A" "FAILED login auth c000006d" "counter-proof: wrong password refused"
has "$A" "FAILED tree share c00000cc" "counter-proof: missing share refused"
has "$A" "FAILED open notfound c0000034" "counter-proof: missing file refused"

echo "== 3. signing mandatory =="
run_case mandatory mandatory "SMB_PASSWORD=gatepass;export SMB_PASSWORD;$S data ls;$S data get big.bin;$S -N data ls"
M="$TMPD/mandatory.txt"
has "$M" "smbctl: ls ok" "signed ls against a mandatory-signing server"
[ "$(digest_of "$M" get 300000)" = "$WANT_BIG" ] && ok "signed get verifies every response signature" || bad "signed get digest '$(digest_of "$M" get 300000)'"
grep -aq "FAILED" "$M" && ok "counter-proof: unsigned session refused by the mandatory server" || bad "unsigned session was accepted"

echo "SMBGUEST: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
