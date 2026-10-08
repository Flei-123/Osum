#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/stab/net.sh -- Dell stability, parts 3 and 4: what does the bridge helper
# (jarvisd, transport https, the way the Dell runs it) cost while it is idle, and
# how fast is it back after the network was away?
#
#   bash tools/stab/net.sh [idle_s] [outage_s] [recover_s]
#
# Everything runs in a private network namespace (unshare -n): a throw-away
# bruecke_server.py (the repo copy), a TLS 1.3 front for it (tlsfront.py, test
# certificate), a DNS stub, and a QEMU with user networking in which the guest
# reaches the host loopback as 10.0.2.2. The device key is a fresh one made here
# and pre-paired with the throw-away server -- NEVER the Dell's key.
#
# Measures (one line each, prefixed STABNET):
#   idle:   TLS connections of the guest in <idle_s> seconds (each one is a full
#           handshake on the guest), and the CPU ticks (100 per second) the
#           jarvisd tasks used in that time = percent of one core
#   outage: QEMU `set_link n0 off` for <outage_s> seconds, then on; seconds from
#           link-up to the first connection and to the first poll ("puls") of the
#           new session
#
# STAB_TREE=<worktree> builds the guest (kernel + jarvisd) from another tree, for
# before/after series against an older commit.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
if [ -z "${STABNET_INNER:-}" ]; then
    command -v unshare >/dev/null || { echo "STABNET: skipped, unshare missing"; exit 0; }
    exec env STABNET_INNER=1 unshare -n bash "$0" "$@"
fi
ip link set lo up
cd "$HERE"
IDLE=${1:-60}; OUT=${2:-40}; RECOV=${3:-90}
TREE=${STAB_TREE:-$HERE}
LABEL=${STAB_LABEL:-run}
UP=18091
T=$(mktemp -d)
PIDS=()
cleanup() { for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done; rm -rf "$T"; }
trap cleanup EXIT
for t in qemu-system-x86_64 python3; do command -v $t >/dev/null || { echo "STABNET: skipped, $t missing"; exit 0; }; done
python3 -c 'import cryptography' 2>/dev/null || { echo "STABNET: skipped, python3-cryptography missing"; exit 0; }

# ---- build the guest from $TREE
( cd "$TREE" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
  BRIDGE_PROGS="sh ls cat echo chmod jsig jarvisctl ps sleep kill" bash tools/bridge/build.sh "$T/w0" 0 ) > "$T/build.txt" 2>&1 \
    || { tail -15 "$T/build.txt"; echo "STABNET: build failed"; exit 1; }
K="$T/w0/k.mb"

# ---- certificates, device key, server
python3 "$HERE/tools/hwnet/mkcerts.py" "$T/certs" jarvis.test > /dev/null || exit 1
SEED=$(python3 -c 'import os;print(os.urandom(32).hex())')
PUB=$(python3 - "$SEED" <<'E'
import sys
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization
k = Ed25519PrivateKey.from_private_bytes(bytes.fromhex(sys.argv[1]))
print(k.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw).hex())
E
)
printf '%s\n' "$SEED" > "$T/geraet.key"
mkdir -p "$T/srv"
python3 "$HERE/tools/bruecke-server/bruecke_server.py" --port $UP --bind 127.0.0.1 --wurzel "$T/srv" 2> "$T/server.log" >/dev/null &
PIDS+=($!)
sleep 1.5
ADMIN=$(cat "$T/srv/verwalter.key")
curl -s -X POST -H "X-Bruecke-Verwalter: $ADMIN" -H 'Content-Type: application/json' \
    -d "{\"was\":\"vorab\",\"pubkey\":\"$PUB\"}" http://127.0.0.1:$UP/bruecke/koppeln > "$T/pair.txt" 2>&1
python3 "$HERE/tools/stab/tlsfront.py" --cert "$T/certs/good.pem" --key "$T/certs/good.key" --port 443 --upstream $UP --log "$T/front.log" 2> "$T/front.err" &
PIDS+=($!)
python3 "$HERE/tools/stab/dnsstub.py" 10.0.2.2 53 2> "$T/dns.err" &
PIDS+=($!)
sleep 0.7

# ---- image
cat > "$T/permissions.conf" <<CONF
server         = 10.0.2.2:443
transport      = https
path           = /bruecke/draht
servername     = jarvis.test
roots          = /etc/ssl/roots.pem
commands       = no
screenshot     = no
sysinfo        = yes
watchdog       = 600
CONF
echo "nameserver 10.0.2.2" > "$T/resolv.conf"
cat > "$T/s.sh" <<S
echo ==BOOT==
jarvisd -t 900000 &
sleep 15
echo ==PS0==
ps
sleep $IDLE
echo ==PS1==
ps
sleep $((OUT + RECOV + 5))
echo ==PS2==
ps
echo ==END==
S
python3 "$TREE/tools/osum/mkfs.py" build "$T/d.img" 16384 \
    /bin/ /etc/ /etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/ /t/ \
    "/bin/sh=$T/w0/sh.elf" "/bin/ls=$T/w0/ls.elf" "/bin/cat=$T/w0/cat.elf" "/bin/echo=$T/w0/echo.elf" \
    "/bin/chmod=$T/w0/chmod.elf" "/bin/jsig=$T/w0/jsig.elf" "/bin/jarvisctl=$T/w0/jarvisctl.elf" \
    "/bin/jarvisd=$T/w0/jarvisd.elf" "/bin/ps=$T/w0/ps.elf" "/bin/sleep=$T/w0/sleep.elf" "/bin/kill=$T/w0/kill.elf" \
    "/etc/jarvis/permissions.conf=$T/permissions.conf" \
    "/etc/jarvis/geraet.key=$T/geraet.key@600" \
    "/etc/ssl/roots.pem=$T/certs/ca.pem" \
    "/etc/resolv.conf=$T/resolv.conf" \
    "/t/s.sh=$T/s.sh" > "$T/mkfs.txt" 2>&1 || { tail -5 "$T/mkfs.txt"; echo "STABNET: mkfs failed"; exit 1; }

qmon() { python3 - "$T/mon.sock" "$1" <<'E'
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); time.sleep(0.2)
s.recv(4096); s.sendall((sys.argv[2] + "\n").encode()); time.sleep(0.3); s.recv(4096)
E
}
mono() { python3 -c 'import time;print("%.3f"%time.monotonic())'; }

timeout $((IDLE + OUT + RECOV + 200)) qemu-system-x86_64 -accel "$( [ -w /dev/kvm ] && echo kvm || echo tcg )" -kernel "$K" -m 256 \
    -append "osum nokbd nosched noproc nofs noring3 nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
    -serial "file:$T/serial.txt" -display none -no-reboot \
    -drive "file=$T/d.img,format=raw,if=ide,index=0" \
    -netdev user,id=n0 -device e1000,netdev=n0,mac=52:54:00:aa:bb:cc \
    -monitor "unix:$T/mon.sock,server,nowait" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
QP=$!
PIDS+=($QP)

waitfor() { # <marker> <seconds>
    local n=0
    while [ $n -lt $2 ]; do
        grep -qa "$1" "$T/serial.txt" 2>/dev/null && return 0
        kill -0 $QP 2>/dev/null || return 1
        sleep 1; n=$((n+1))
    done
    return 1
}
waitfor "==PS0==" 240 || { echo "STABNET: guest never reached PS0"; tr -cd '\11\12\15\40-\176' < "$T/serial.txt" | tail -30; tail -5 "$T/front.log" "$T/server.log"; exit 1; }
T_PS0=$(mono)
waitfor "==PS1==" $((IDLE + 60)) || { echo "STABNET: no PS1"; exit 1; }
T_PS1=$(mono)
sleep 2
T_OFF=$(mono); qmon "set_link n0 off"
sleep "$OUT"
T_ON=$(mono); qmon "set_link n0 on"
waitfor "==END==" $((RECOV + 60))
sleep 1
tr -cd '\11\12\15\40-\176' < "$T/serial.txt" > "$T/serial.klar"

ticks_of() { # <marker> -> sum of TICKS of the jarvisd tasks listed after the marker
    awk -v m="$1" '$0 ~ m {on=1; next} on && /==/ {on=0} on && /jarvisd/ {s+=$6} END{print s+0}' "$T/serial.klar"
}
P0=$(ticks_of "==PS0=="); P1=$(ticks_of "==PS1==")
DT=$(python3 -c "print(round($T_PS1-$T_PS0,1))")
CONNS=$(awk -v a="$T_PS0" -v b="$T_PS1" '$1=="CONN" && $2>=a && $2<=b' "$T/front.log" | wc -l)
PULS=$(awk -v a="$T_PS0" -v b="$T_PS1" '$1=="CONN" && $2>=a && $2<=b && $4=="puls"' "$T/front.log" | wc -l)
python3 - "$P0" "$P1" "$DT" "$CONNS" "$PULS" "$LABEL" <<'E'
import sys
p0, p1, dt, conns, puls, label = int(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), sys.argv[6]
d = p1 - p0
print("STABNET[%s]: idle %.0f s: %d connections (%d polls) = %.1f per minute; jarvisd CPU %d ticks = %.1f %% of one core"
      % (label, dt, conns, puls, conns * 60.0 / dt, d, d / (dt * 100.0) * 100))
E
FIRST=$(awk -v a="$T_ON" '$1=="CONN" && $2>=a {print $2; exit}' "$T/front.log")
FIRSTP=$(awk -v a="$T_ON" '$1=="CONN" && $2>=a && $4=="puls" {print $2; exit}' "$T/front.log")
LASTOK=$(awk -v a="$T_OFF" '$1=="CONN" && $2<a {t=$2} END{print t}' "$T/front.log")
python3 - "$T_ON" "$FIRST" "$FIRSTP" "$OUT" "$LASTOK" "$T_OFF" "$LABEL" <<'E'
import sys
on = float(sys.argv[1]); out = sys.argv[4]; label = sys.argv[7]
def rel(x): return "%.1f s" % (float(x) - on) if x else "NEVER"
print("STABNET[%s]: outage %s s: first connection %s after link-up, first poll of a new session %s after link-up"
      % (label, out, rel(sys.argv[2]), rel(sys.argv[3])))
E
grep -a "jarvisd:" "$T/serial.klar" | head -${STAB_SHOW:-0}
[ -n "${STAB_KEEP:-}" ] && { mkdir -p "$STAB_KEEP"; cp "$T/serial.klar" "$T/front.log" "$T/server.log" "$STAB_KEEP/"; }
exit 0
