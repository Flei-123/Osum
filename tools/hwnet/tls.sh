#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hwnet/tls.sh -- ROUND HWNET: HTTPS OUT OF RING 3, AND THE REFUSALS.
#
# Osum had no TLS. It also, all along, had the whole of Firn's round-B5
# TLS work sitting in `vendor/firn/lib/tls/` and `lib/std/crypto/`,
# pinned by `vendor/firn/COMMIT` and never used -- because every program
# under `kernel/user/` is `profile kernel`, and a record layer needs a
# heap.
#
# `kernel/app/fetch.fi` is the second shape of a ring-3 program:
# `--profile=app`, the FULL Firn library, linked with `kernel/user/user.ld`
# and WITHOUT `crt.s`, because Firn's own `_start` already does what Osum's
# loader expects. It works because Osum's system calls carry Linux's
# numbers (round K4) and its argument block has Linux's shape.
#
# WHAT IS MEASURED HERE, and in this order:
#
#   1. the program builds and fits: one object, no undefined symbols
#   2. against `openssl s_server` -- a TLS implementation this repository
#      did not write -- over the e1000 driver of this round:
#        good certificate    -> verify OK and a body
#        expired             -> REFUSED, and the reason is `expired`
#        wrong name          -> REFUSED, `wrong_name`
#        unknown issuer      -> REFUSED, `unknown_issuer`
#        no trust store      -> REFUSED, nothing is trusted
#      THE REFUSALS ARE THE MEASUREMENT. A TLS client that accepts
#      everything is worse than no TLS at all, and the only way to know
#      which one this is, is to hand it four bad certificates.
#   3. if there is a route to the public internet: the same program
#      against a real host, and the SHA-256 of the body held against what
#      `curl` gets on this machine. Skipped, loudly, when there is no
#      route -- not silently passed.
#
# THIS CRYPTOGRAPHY HAS NOT BEEN AUDITED. See docs/REALHW.md.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

NIC=${HWNET_NIC:-e1000}
NS=hwtls-$$
V0=tl0-$$
V1=hw1
V2=tl2-$$
V3=hw3
QPORT=$(( 14000 + ($$ % 400) * 2 ))
BPORT=$(( QPORT + 1 ))
TMPD=$(mktemp -d)
BRPID=""
SRVPID=""
NATED=0
cleanup() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    [ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null
    [ "$NATED" = 1 ] && iptables -t nat -D POSTROUTING -s 10.200.0.0/24 -j MASQUERADE 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    ip link del "$V2" 2>/dev/null
    rm -rf "$TMPD"
}
trap cleanup EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' is missing"; }
num() { local n=$1 v=$2 o=$3 w=$4
    if [ -z "${v:-}" ]; then bad "$n: no number (expected $o $w)"; return; fi
    if [ "$v" -"$o" "$w" ] 2>/dev/null; then ok "$n: $v"; else bad "$n: $v, expected $o $w"; fi
}
fval() { grep -aoE "^fetch: $2 [0-9a-f]+" "$1" 2>/dev/null | tail -1 | awk '{print $3}'; }

for t in qemu-system-x86_64 ip openssl python3 curl; do
    command -v "$t" >/dev/null 2>&1 || { echo "HWNETTLS: skipped, $t is missing"; exit 0; }
done
python3 -c 'import cryptography' 2>/dev/null || {
    echo "HWNETTLS: skipped, python3-cryptography is missing"; exit 0; }
ip netns del "$NS" 2>/dev/null
ip netns add "$NS" 2>/dev/null || { echo "HWNETTLS: skipped, no network namespaces"; exit 0; }
ip netns del "$NS" 2>/dev/null

# =====================================================================
echo "== 1. the program: the full Firn library in ring 3 =="
# =====================================================================
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
if FIRNLIB="$ROOT/vendor/firn/lib" vendor/firn/bin/firnc -c --profile=app \
        -o "$TMPD/fetch.o" kernel/app/fetch.fi > "$TMPD/cc.log" 2>&1; then
    ok "firnc --profile=app: fetch.fi with std.rt, std.net, tls.tls and tls.x509"
else
    bad "fetch.fi does not compile"; head -10 "$TMPD/cc.log" | sed 's/^/        /'
    echo "HWNETTLS: $pass passed, $fail failed"; exit 1
fi
undef=$(nm -u "$TMPD/fetch.o" 2>/dev/null | awk '{print $NF}' | sed '/^$/d')
[ -z "$undef" ] && ok "not one undefined symbol -- it needs no crt.s and no libc" \
                || bad "undefined: $undef"
ld -T kernel/user/user.ld -o "$TMPD/fetch.elf" "$TMPD/fetch.o" 2>"$TMPD/ld.err" \
    && ok "ld with kernel/user/user.ld: three page-aligned segments at 0x40100000" \
    || { bad "ld failed"; head -3 "$TMPD/ld.err"; }
strip --strip-all "$TMPD/fetch.elf" 2>/dev/null
SZ=$(stat -c%s "$TMPD/fetch.elf")
num "the program on the disk, in octets" "$SZ" le 2134016
ok "  (that is $SZ octets: TLS 1.3, X.509, RSA, ECDSA, X25519, AES-GCM, ChaCha20)"

# the rest of the userland comes out of the round's own build
bash tools/hwnet/build.sh "$TMPD/s0" 0 > "$TMPD/b0.txt" 2>&1 \
    || { bad "the kernel does not build"; echo "HWNETTLS: $pass passed, $fail failed"; exit 1; }
K="$TMPD/s0/k.mb"
python3 tools/hwnet/mkcerts.py "$TMPD/certs" osum.test > "$TMPD/certs.txt" 2>&1 \
    && ok "the test certificates were made with Python's cryptography, not with this repository" \
    || { bad "mkcerts.py failed"; cat "$TMPD/certs.txt"; }
gcc -O2 -o "$TMPD/bridge" tools/net/bridge.c 2>/dev/null || bad "bridge.c"

image() { # <store-file> <image>
    python3 tools/osum/mkfs.py build "$2" 16384 \
        /bin/ /etc/ /etc/ssl/ \
        "/bin/sh=$TMPD/s0/sh.elf" "/bin/fetch=$TMPD/fetch.elf" \
        "/etc/ssl/roots.pem=$1" > "$TMPD/mkfs.txt" 2>&1
}

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
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null; BRPID=""
    ip netns del "$NS" 2>/dev/null; ip link del "$V0" 2>/dev/null
}

run_osum() { # <image> <script> <out>
    timeout 200 qemu-system-x86_64 -kernel "$K" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 nic nip=10.9.0.2/24 ngw=10.9.0.1 nsvc=0 nwait=0 script=$2;exit" \
        -serial "file:$3" -display none -no-reboot \
        -drive "file=$1,format=raw,if=ide,index=0" \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "$NIC,netdev=n0,mac=52:54:00:aa:bb:cc" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}

# =====================================================================
echo "== 2. against openssl s_server, four bad certificates and one good =="
# =====================================================================
# case:name:store:expected line
CASES="good:osum.test:ca:fetch: verify OK
expired:osum.test:ca:fetch: verify REFUSED expired
wrong:osum.test:ca:fetch: verify REFUSED wrong_name
rogue:osum.test:ca:fetch: verify REFUSED unknown_issuer
good:osum.test:empty:fetch: verify REFUSED unknown_issuer"
: > "$TMPD/empty.pem"
i=0
while IFS= read -r line; do
    i=$((i+1))
    cert=$(echo "$line" | cut -d: -f1)
    name=$(echo "$line" | cut -d: -f2)
    storename=$(echo "$line" | cut -d: -f3)
    want=$(echo "$line" | cut -d: -f4-)
    if [ "$storename" = empty ]; then store="$TMPD/empty.pem"; else store="$TMPD/certs/ca.pem"; fi
    image "$store" "$TMPD/img$i.raw" || bad "mkfs for case $i"
    wire_up
    ip netns exec "$NS" openssl s_server -accept 4433 \
        -cert "$TMPD/certs/$cert.pem" -key "$TMPD/certs/$cert.key" \
        -www -tls1_3 -naccept 2 > "$TMPD/srv$i.log" 2>&1 & SRVPID=$!
    sleep 0.7
    run_osum "$TMPD/img$i.raw" "fetch -q -n $name https://10.9.0.1:4433/" "$TMPD/c$i.txt"
    kill "$SRVPID" 2>/dev/null; SRVPID=""
    wire_down
    tag="$cert/$storename"
    has "$TMPD/c$i.txt" "$want" "$tag: $want"
    if [ "$cert" = good ] && [ "$storename" = ca ]; then
        num "$tag: the cipher suite (4865 = TLS_AES_128_GCM_SHA256)" \
            "$(fval "$TMPD/c$i.txt" suite)" eq 4865
        num "$tag: octets of the answer" "$(fval "$TMPD/c$i.txt" octets)" ge 100
        num "$tag: TLS records that came in" "$(fval "$TMPD/c$i.txt" records_in)" ge 3
        grep -qa 'openssl' "$TMPD/srv$i.log" && ok "$tag: and it was openssl on the other side" \
            || ok "$tag: (the server log says nothing, the handshake did)"
    else
        grep -qa "fetch: octets" "$TMPD/c$i.txt" \
            && bad "$tag: octets were fetched THROUGH a refused certificate" \
            || ok "$tag: and NOTHING was fetched through it"
    fi
done <<EOF
$CASES
EOF

# =====================================================================
echo "== 3. the public internet, if there is a route to it =="
# =====================================================================
HOSTN=${HWNET_HOST:-example.com}
IP=$(getent ahostsv4 "$HOSTN" 2>/dev/null | awk '{print $1; exit}')
if [ -z "$IP" ] || ! curl -s -m 8 -o /dev/null "https://$HOSTN/" 2>/dev/null; then
    echo "   SKIPPED: this machine has no route to $HOSTN. Nothing is claimed."
else
    python3 tools/hwnet/mkroots.py "$TMPD/roots.pem" > "$TMPD/roots.txt" 2>&1 \
        && ok "the trust store: $(cat "$TMPD/roots.txt")" || bad "mkroots.py failed"
    image "$TMPD/roots.pem" "$TMPD/inet.raw" || bad "mkfs for the internet run"
    # the wire, plus a second pair out of the namespace and NAT on this host
    wire_up
    ip link add "$V2" type veth peer name "$V3"
    ip link set "$V3" netns "$NS"
    ip netns exec "$NS" ip addr add 10.200.0.2/24 dev "$V3"
    ip netns exec "$NS" ip link set "$V3" up
    ip netns exec "$NS" ip route add default via 10.200.0.1
    ip netns exec "$NS" sysctl -q -w net.ipv4.ip_forward=1
    ip netns exec "$NS" iptables -t nat -A POSTROUTING -s 10.9.0.0/24 -o "$V3" -j MASQUERADE
    ip addr add 10.200.0.1/24 dev "$V2"; ip link set "$V2" up
    sysctl -q -w net.ipv4.ip_forward=1
    iptables -t nat -A POSTROUTING -s 10.200.0.0/24 -j MASQUERADE && NATED=1
    run_osum "$TMPD/inet.raw" "fetch -q -n $HOSTN https://$IP/" "$TMPD/inet.txt"
    wire_down
    [ "$NATED" = 1 ] && iptables -t nat -D POSTROUTING -s 10.200.0.0/24 -j MASQUERADE 2>/dev/null
    NATED=0
    ip link del "$V2" 2>/dev/null
    I="$TMPD/inet.txt"
    has "$I" "fetch: verify OK" "$HOSTN: the chain of a REAL server verified against the Mozilla roots"
    num "$HOSTN: certificates in the chain" "$(fval "$I" certs)" ge 2
    num "$HOSTN: octets of the answer" "$(fval "$I" octets)" ge 100
    OSHA=$(grep -aoE '^fetch: bodysha [0-9a-f]+' "$I" | tail -1 | awk '{print $3}')
    CSHA=$(curl -s "https://$HOSTN/" | sha256sum | awk '{print $1}')
    if [ -n "$OSHA" ] && [ "$OSHA" = "$CSHA" ]; then
        ok "$HOSTN: THE SAME OCTETS AS curl, to the digest: $OSHA"
    else
        bad "$HOSTN: osum $OSHA, curl $CSHA"
    fi
fi

echo "HWNETTLS: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
