#!/usr/bin/env bash
# tools/tunnel/run.sh -- ROUND TUNNEL: THE WHOLE THING, MEASURED.
#
# Five stages, and each one measures against something this repository did
# not write:
#
#   1. THE PRIMITIVES against the test vectors printed in RFC 7693, RFC
#      8439, RFC 7748 and draft-irtf-cfrg-xchacha, and against libb2,
#      OpenSSL and libsodium over generated inputs.
#      (tools/tunnel/vectors.py)
#   2. THE PROTOCOL against the WireGuard implementation IN THE LINUX
#      KERNEL, over a veth pair in a network namespace. Linux's own
#      `ping` goes through it. (tools/tunnel/against_wg.py)
#   3. THE OBFUSCATION: the AmneziaWG parameters really change the wire,
#      and a stock Linux WireGuard ignores what comes out.
#      (tools/tunnel/amnezia.py)
#   4. THE PROXY against a real SOCKS5 server, a real HTTP proxy and the
#      real Tor daemon. (tools/tunnel/proxy.py)
#   5. THE KERNEL. Osum itself, in QEMU, on a virtio-net card, with the
#      tunnel in `kernel/wg.fi` between `stack.net_output` and the card.
#      The wire is round K8's: QEMU's UDP socket backend, `tools/net/
#      bruecke` and AF_PACKET on a veth into a namespace, because
#      `/dev/net/tun` cannot be created here. THE KILL SWITCH IS MEASURED
#      HERE and nowhere else: the tunnel is broken on purpose and the
#      octets that reach `virtio.tx_frame` are counted. The target is 0.
#
# Stages 2 to 5 need root (network namespaces) and are skipped without it,
# loudly.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}

NS=wgt-$$
V0=wt0-$$
V1=wt1
OSUM_IP=10.9.0.2
HOST_IP=10.9.0.1
OSUM_TUN=10.91.0.1
HOST_TUN=10.91.0.2
WGPORT=51820
QPORT=$(( 7000 + ($$ % 400) * 2 ))
BPORT=$(( QPORT + 1 ))

TMPD=$(mktemp -d)
BRPID=""
cleanup() {
    [ -n "$BRPID" ] && kill "$BRPID" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    rm -rf "$TMPD"
}
trap cleanup EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note() { printf '  --    %s\n' "$1"; }

mkdir -p .probe

# `ONLY=5` runs just the kernel stage. The four host stages take minutes
# and stage 5 is the one that gets iterated on.
ONLY=${ONLY:-}

if [ "$ONLY" = 5 ]; then
    $FIRNC tools/tunnel/oracle.fi -o .probe/oracle 2>/dev/null
    $FIRNC tools/tunnel/peer.fi -o .probe/peer 2>/dev/null
    $FIRNC tools/tunnel/socksdrv.fi -o .probe/socksdrv 2>/dev/null
fi

# =====================================================================
[ -z "$ONLY" ] && echo "== 1. the four primitives against their RFCs =="
# =====================================================================
[ -z "$ONLY" ] && $FIRNC tools/tunnel/oracle.fi -o .probe/oracle 2>"$TMPD/e" \
    && [ -z "$ONLY" ] && ok "tools/tunnel/oracle.fi builds against lib/crypto/" \
    || { bad "the oracle does not build"; head -6 "$TMPD/e" | sed 's/^/        /'; }
if [ -x .probe/oracle ] && [ -z "$ONLY" ]; then
    if python3 tools/tunnel/vectors.py >"$TMPD/vec" 2>&1; then
        ok "$(tail -1 "$TMPD/vec")"
        grep -E '^  [A-Za-z]' "$TMPD/vec" | sed 's/^/     /'
    else
        bad "test vectors failed"
        tail -20 "$TMPD/vec" | sed 's/^/        /'
    fi
fi

# =====================================================================
echo "== 2. the protocol against the Linux kernel's WireGuard =="
# =====================================================================
[ -n "$ONLY" ] || $FIRNC tools/tunnel/peer.fi -o .probe/peer 2>"$TMPD/e" \
    && ok "tools/tunnel/peer.fi builds against lib/wg/proto.fi" \
    || { bad "peer.fi does not build"; head -6 "$TMPD/e" | sed 's/^/        /'; }
[ -n "$ONLY" ] || $FIRNC tools/tunnel/socksdrv.fi -o .probe/socksdrv 2>"$TMPD/e" \
    && ok "tools/tunnel/socksdrv.fi builds against lib/socks/" \
    || { bad "socksdrv.fi does not build"; head -6 "$TMPD/e" | sed 's/^/        /'; }

HAVE_ROOT=0
[ "$(id -u)" = 0 ] && HAVE_ROOT=1
command -v wg >/dev/null 2>&1 || { note "wireguard-tools is missing"; HAVE_ROOT=0; }
if ip netns add "probe-$$" 2>/dev/null; then ip netns del "probe-$$"; else
    note "network namespaces are not available here"; HAVE_ROOT=0; fi

if [ "$HAVE_ROOT" = 1 ] && [ -x .probe/peer ] && [ -z "$ONLY" ]; then
    if python3 tools/tunnel/against_wg.py >"$TMPD/wg" 2>&1; then
        ok "$(tail -1 "$TMPD/wg")"
        grep -E '^  ' "$TMPD/wg" | sed 's/^/     /'
    else
        bad "the run against Linux failed"
        tail -25 "$TMPD/wg" | sed 's/^/        /'
    fi
else
    note "stage 2 skipped: needs root, wireguard-tools and namespaces"
fi

# =====================================================================
echo "== 3. the AmneziaWG obfuscation =="
# =====================================================================
if [ "$HAVE_ROOT" = 1 ] && [ -x .probe/peer ] && [ -z "$ONLY" ]; then
    if python3 tools/tunnel/amnezia.py >"$TMPD/awg" 2>&1; then
        ok "$(grep -E '^all ' "$TMPD/awg" | head -1)"
        grep -E '^  ' "$TMPD/awg" | sed 's/^/     /'
    else
        bad "the AmneziaWG run failed"
        tail -20 "$TMPD/awg" | sed 's/^/        /'
    fi
else
    note "stage 3 skipped"
fi

# =====================================================================
echo "== 4. SOCKS5, HTTP CONNECT and the real Tor daemon =="
# =====================================================================
if [ -x .probe/socksdrv ] && [ -z "$ONLY" ]; then
    if python3 tools/tunnel/proxy.py >"$TMPD/px" 2>&1; then
        ok "$(grep -E '^all ' "$TMPD/px" | head -1)"
        grep -E '^  ' "$TMPD/px" | sed 's/^/     /'
    else
        bad "the proxy run failed"
        tail -20 "$TMPD/px" | sed 's/^/        /'
    fi
fi

# =====================================================================
echo "== 5. the tunnel inside the Osum kernel =="
# =====================================================================
for t in qemu-system-x86_64 gcc ip python3; do
    command -v "$t" >/dev/null 2>&1 || { note "stage 5 skipped, $t missing"; exit_now=1; }
done
if [ "${exit_now:-0}" = 1 ] || [ "$HAVE_ROOT" != 1 ]; then
    note "stage 5 skipped: needs root, qemu and gcc"
    echo
    echo "  $pass passed, $fail failed"
    [ "$fail" = 0 ] || exit 1
    exit 0
fi

./tools/build-kernel.sh "$TMPD/osum.mb" >"$TMPD/build" 2>&1 \
    && ok "the kernel builds with kernel/wg.fi in it" \
    || { bad "the kernel does not build"; tail -8 "$TMPD/build" | sed 's/^/        /'; }
gcc -O2 -o "$TMPD/bruecke" tools/net/bruecke.c 2>"$TMPD/gcc.err" \
    && ok "the UDP/AF_PACKET wire is built" \
    || bad "bruecke.c does not compile"

# --- the keys. The Linux side's are made by `wg`, ours by `openssl rand`
# --- and clamped the way RFC 7748 asks; the kernel prints the public key
# --- it derived and it is compared with what `wg pubkey` says.
OUR_PRIV=$(python3 -c "
import os
k=bytearray(os.urandom(32)); k[0]&=248; k[31]=(k[31]&127)|64
print(bytes(k).hex())")
OUR_PUB=$(python3 -c "
import base64
from nacl.bindings import crypto_scalarmult_base
print(crypto_scalarmult_base(bytes.fromhex('$OUR_PRIV')).hex())")
OUR_PUB_B64=$(python3 -c "
import base64
print(base64.b64encode(bytes.fromhex('$OUR_PUB')).decode())")
LX_PRIV=$(wg genkey)
LX_PUB=$(echo "$LX_PRIV" | wg pubkey)
LX_PUB_HEX=$(python3 -c "
import base64
print(base64.b64decode('$LX_PUB').hex())")

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
    ip netns exec "$NS" ethtool -K "$V1" tx off rx off tso off gso off gro off \
        >/dev/null 2>&1
    "$TMPD/bruecke" "$V0" "$BPORT" "$QPORT" 2>"$TMPD/br.log" &
    BRPID=$!
    sleep 0.4
}

wg_up() { # set up a Linux wg0 in the namespace
    cat > "$TMPD/wg.conf" <<EOF
[Interface]
PrivateKey = $LX_PRIV
ListenPort = $WGPORT

[Peer]
PublicKey = $OUR_PUB_B64
AllowedIPs = $OSUM_TUN/32
EOF
    chmod 600 "$TMPD/wg.conf"
    ip netns exec "$NS" ip link add wg0 type wireguard
    ip netns exec "$NS" wg setconf wg0 "$TMPD/wg.conf"
    ip netns exec "$NS" ip addr add "$HOST_TUN/24" dev wg0
    ip netns exec "$NS" ip link set wg0 up
}

run_osum() { # append, seconds, logfile
    timeout "$2" qemu-system-x86_64 -kernel "$TMPD/osum.mb" -m 512 \
        -append "$1" -nographic -no-reboot \
        -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
        -device "virtio-net-pci,netdev=n0,mac=52:54:00:aa:bb:cd" \
        -serial mon:stdio </dev/null >"$3" 2>&1
}

val() { grep -aoE "$2=[0-9]+" "$1" 2>/dev/null | tail -1 | cut -d= -f2; }

# --------------------------------------------------------------------
echo "-- 5a. the kernel derives the same public key as wg(8) --"
# --------------------------------------------------------------------
wire_up
run_osum "nic nip=$OSUM_IP nprefix=24 ngw=$HOST_IP nsvc=0 nwait=60 \
wgpriv=$OUR_PRIV wgaddr=$OSUM_TUN/24 wgport=$WGPORT" 60 "$TMPD/a.log"
KPUB=$(grep -ao 'pub=[0-9a-f]*' "$TMPD/a.log" | tail -1 | cut -d= -f2)
if [ "$KPUB" = "$OUR_PUB" ]; then
    ok "X25519 in the kernel agrees with libsodium: ${KPUB:0:16}..."
else
    bad "the kernel's public key is $KPUB, expected $OUR_PUB"
fi
grep -qa 'wg: port=' "$TMPD/a.log" && ok "kernel/wg.fi comes up at boot" \
    || bad "no 'wg:' line -- the tunnel did not start"
kill $BRPID 2>/dev/null; BRPID=""

# --------------------------------------------------------------------
echo "-- 5b. the handshake, kernel to kernel --"
# --------------------------------------------------------------------
wire_up
wg_up
APPEND="nic nip=$OSUM_IP nprefix=24 ngw=$HOST_IP nsvc=0 nwait=110 \
wgpriv=$OUR_PRIV wgpeer=$LX_PUB_HEX wgep=$HOST_IP:$WGPORT \
wgallow=$HOST_TUN/32 wgaddr=$OSUM_TUN/24 wgport=$WGPORT wgup"
run_osum "$APPEND" 110 "$TMPD/b.log" &
QRUN=$!
sleep 14
LATEST=$(ip netns exec "$NS" wg show wg0 latest-handshakes 2>/dev/null | awk '{print $2}')
XFER=$(ip netns exec "$NS" wg show wg0 transfer 2>/dev/null | awk '{print $2}')
if [ -n "${LATEST:-}" ] && [ "${LATEST:-0}" != 0 ]; then
    ok "the Linux kernel completed a handshake with Osum"
else
    bad "no handshake: wg show says '${LATEST:-nothing}'"
fi
if [ "${XFER:-0}" -gt 0 ] 2>/dev/null; then
    ok "Linux received $XFER octets from the Osum tunnel"
else
    bad "Linux received nothing from the tunnel"
fi
# The proof that traffic really flows: Linux pings the address Osum has
# INSIDE the tunnel. The echo request is encrypted by the Linux kernel,
# decrypted by kernel/wg.fi, handed to inet.fi as an ordinary frame,
# answered by Osum's own ICMP, encrypted again on the way back.
PING=$(ip netns exec "$NS" ping -c 4 -i 0.5 -W 3 "$OSUM_TUN" 2>&1)
GOT=$(echo "$PING" | grep -oE '[0-9]+ received' | grep -oE '^[0-9]+')
RTT=$(echo "$PING" | grep -oE 'rtt.*' | head -1)
if [ "${GOT:-0}" -ge 2 ] 2>/dev/null; then
    ok "Linux pinged Osum THROUGH the tunnel: $GOT of 4, $RTT"
else
    bad "the ping through the tunnel got $GOT of 4 replies"
fi
wait $QRUN 2>/dev/null
HSOK=$(grep -aoE 'hs_ok=[0-9]+' "$TMPD/b.log" | tail -1 | cut -d= -f2)
note "kernel counters: $(grep -aoE 'wgstat:.*' "$TMPD/b.log" | tail -1)"
kill $BRPID 2>/dev/null; BRPID=""

# --------------------------------------------------------------------
echo "-- 5c. THE KILL SWITCH: 0 octets on the wire while the tunnel is down --"
# --------------------------------------------------------------------
#
# THE COUNT IS NOT THE KERNEL'S OWN. A kill switch that reports its own
# success is a claim, not a measurement. `tcpdump` runs INSIDE the
# namespace on the far end of the veth and records everything that
# arrives; a Python script then counts the octets of IPv4 packets whose
# source is Osum. Nothing in the kernel can influence that number.
#
# ARP IS COUNTED SEPARATELY AND NOT AS A LEAK, and that is a decision
# rather than an omission: `kernel/wg.fi` lets ARP through on purpose,
# because without it the endpoint cannot be resolved and the tunnel could
# never come back up. An ARP frame carries a MAC and an IP that the local
# segment already knows and it does not leave the segment. Everything
# else is a leak.
#
# THE COUNTER-CHECK COMES FIRST. The same kernel, the same service, the
# same dead endpoint, only `wgkill` missing -- if THAT run does not leak,
# the measurement below means nothing.
DEAD_EP=10.9.0.250 # nothing answers there, so the tunnel never comes up
BASE="nic nip=$OSUM_IP nprefix=24 ngw=$HOST_IP nsvc=4 nport=9099 \
nbytes=65536 nwait=45 wgpriv=$OUR_PRIV wgpeer=$LX_PUB_HEX \
wgep=$DEAD_EP:$WGPORT wgallow=0.0.0.0/0 wgaddr=$OSUM_TUN/24 \
wgport=$WGPORT"

count_wire() { # pcap-file -> "ip_octets arp_frames"
    python3 - "$1" "$OSUM_IP" <<'PYEOF'
import struct, sys
path, osum = sys.argv[1], sys.argv[2]
want = bytes(int(x) for x in osum.split("."))
ip_octets = 0
arp = 0
try:
    d = open(path, "rb").read()
except OSError:
    print("0 0"); raise SystemExit
if len(d) < 24:
    print("0 0"); raise SystemExit
magic = d[:4]
if magic == b"\xd4\xc3\xb2\xa1":
    end, nano = "<", False
elif magic == b"\xa1\xb2\xc3\xd4":
    end, nano = ">", False
elif magic == b"\x4d\x3c\xb2\xa1":
    end, nano = "<", True
elif magic == b"\xa1\xb2\x3c\x4d":
    end, nano = ">", True
else:
    print("0 0"); raise SystemExit
at = 24
while at + 16 <= len(d):
    _, _, caplen, _ = struct.unpack_from(end + "IIII", d, at)
    at += 16
    pkt = d[at:at + caplen]
    at += caplen
    if len(pkt) < 14:
        continue
    et = struct.unpack_from("!H", pkt, 12)[0]
    if et == 0x0806:
        arp += 1
    elif et == 0x0800 and len(pkt) >= 34:
        if pkt[26:30] == want:
            ip_octets += len(pkt) - 14
print("%d %d" % (ip_octets, arp))
PYEOF
}

sniff_run() { # append, pcap
    wire_up
    ip netns exec "$NS" timeout 55 tcpdump -i "$V1" -n -s 128 -U \
        -w "$2" >/dev/null 2>&1 &
    local TDPID=$!
    sleep 1
    run_osum "$1" 50 "$TMPD/sniff.log"
    sleep 1
    kill $TDPID 2>/dev/null
    wait $TDPID 2>/dev/null
    kill $BRPID 2>/dev/null; BRPID=""
}

sniff_run "$BASE" "$TMPD/leak.pcap"
cp "$TMPD/sniff.log" "$TMPD/leak.log"
read LEAK_IP LEAK_ARP <<< "$(count_wire "$TMPD/leak.pcap")"

sniff_run "$BASE wgkill" "$TMPD/kill.pcap"
cp "$TMPD/sniff.log" "$TMPD/kill.log"
read KILL_IP KILL_ARP <<< "$(count_wire "$TMPD/kill.pcap")"
KILLED=$(grep -aoE 'wgkilled=[0-9]+' "$TMPD/kill.log" | tail -1 | cut -d= -f2)

if [ "${LEAK_IP:-0}" -gt 0 ] 2>/dev/null; then
    ok "counter-check: WITHOUT wgkill the same kernel put ${LEAK_IP} IP octets on the wire"
else
    bad "the counter-check leaked nothing (${LEAK_IP:-?}) -- the measurement below is meaningless"
fi
if [ "${KILL_IP:-1}" = 0 ]; then
    ok "KILL SWITCH: 0 IP octets on the wire, counted by tcpdump outside the kernel"
else
    bad "KILL SWITCH LEAKED ${KILL_IP} IP octets"
fi
note "ARP frames, allowed on purpose: ${LEAK_ARP:-?} without, ${KILL_ARP:-?} with the switch"
[ -n "${KILLED:-}" ] && note "the kernel says it refused ${KILLED} octets"
note "kernel counters with the switch: $(grep -aoE 'wg: [a-z_]+=[0-9]+' "$TMPD/kill.log" | tr '\n' ' ')"

echo
echo "  $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
