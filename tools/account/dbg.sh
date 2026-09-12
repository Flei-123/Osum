#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/account/dbg.sh -- die kurze Schleife zum Suchen von Fehlern.
#
# Baut Kern, Programm, Zertifikate, Netzraum, Attrappe und ein Abbild --
# und fuehrt DANN genau EINE Gast-Befehlszeile aus, deren serielle
# Ausgabe vollstaendig auf den Schirm kommt. run.sh misst, dbg.sh zeigt.
#
#   bash tools/account/dbg.sh 'konto anmelden --anbieter jarvis ...'
#
# Mit BAUEN=0 wird ein vorhandener Aufbau aus /tmp/konto-dbg weiter
# benutzt (dann dauert ein Durchgang Sekunden statt Minuten).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=${TMPD:-/tmp/konto-dbg}
mkdir -p "$TMPD"
NS=kontodbg
V0=kd0
V1=kd1
BPORT=15900
QPORT=15901
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}

aufraeumen() {
    [ -n "${SRVPID:-}" ] && kill "$SRVPID" 2>/dev/null
    [ -n "${BRPID:-}" ] && kill "$BRPID" 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$V0" 2>/dev/null
    return 0
}
trap aufraeumen EXIT

if [ "${BAUEN:-1}" = "1" ]; then
    echo "-- baue Programm"
    FIRNLIB="$ROOT/vendor/firn/lib" "$FIRNC" -c --profile=app \
        -o "$TMPD/konto.o" kernel/app/account.fi > "$TMPD/cc.log" 2>&1 \
        || { echo "FIRNC:"; tail -20 "$TMPD/cc.log"; exit 1; }
    ld -m elf_x86_64 -T kernel/user/user.ld -o "$TMPD/konto.elf" "$TMPD/konto.o" \
        > "$TMPD/ld.log" 2>&1 || { echo "LD:"; cat "$TMPD/ld.log"; exit 1; }
    echo "-- baue Kern"
    HWNET_PROGS="sh ls cat echo settings" bash tools/hwnet/build.sh "$TMPD/s0" 0 \
        > "$TMPD/b0.txt" 2>&1 || { tail -10 "$TMPD/b0.txt"; exit 1; }
    python3 tools/hwnet/mkcerts.py "$TMPD/certs" konto.test > "$TMPD/certs.txt" 2>&1
    gcc -O2 -o "$TMPD/bridge" tools/net/bridge.c 2>/dev/null
    printf 'richtig\n' > "$TMPD/pw_gut"
    printf 'falsch\n'  > "$TMPD/pw_schlecht"
    : > "$TMPD/leer"
    printf 'root:x:0:0:root:/:/bin/sh\n' > "$TMPD/passwd"
    printf 'lang=de\n' > "$TMPD/locale.conf"
    mkdir -p "$TMPD/eigenordner/konten"
    python3 - "$TMPD/eigenordner/konten/lokal" <<'PY'
import hashlib, sys
salz = bytes(range(16))
pruef = hashlib.pbkdf2_hmac("sha256", b"richtig", salz, 8192, 32)
open(sys.argv[1], "w", encoding="utf-8").write(
    "eigen1\nkennung\tlokal\nsalz\t%s\nrunden\t8192\npruef\t%s\n"
    "subjekt\tlokal-1\nanzeige\tLokal\n" % (salz.hex(), pruef.hex()))
PY
fi
K="$TMPD/s0/k.mb"

if [ "${ABBILD:-1}" = "1" ]; then
    python3 tools/osum/mkfs.py build "$TMPD/d.img" 24576 \
        /bin/ /etc/ /etc/ssl/ /usr/ /usr/share/ /usr/share/locale/ \
        /usr/share/locale/en/ /usr/share/locale/de/ \
        /users/ /users/justin/ /users/justin/config/ \
        /eigen/ /eigen/konten/ \
        "/bin/sh=$TMPD/s0/sh.elf" \
        "/bin/ls=$TMPD/s0/ls.elf" \
        "/bin/cat=$TMPD/s0/cat.elf" \
        "/bin/echo=$TMPD/s0/echo.elf" \
        "/bin/konto=$TMPD/konto.elf" \
        "/etc/ssl/roots.pem=$TMPD/certs/ca.pem" \
        "/etc/passwd=$TMPD/passwd" \
        "/etc/locale.conf=$TMPD/locale.conf" \
        "/etc/konten.conf=$TMPD/konten.conf" \
        "/usr/share/locale/en/messages=$ROOT/locale/en/messages" \
        "/usr/share/locale/de/messages=$ROOT/locale/de/messages" \
        "/pw_gut=$TMPD/pw_gut" \
        "/pw_schlecht=$TMPD/pw_schlecht" \
        "/pw2=$TMPD/pw2" \
        "/leer=$TMPD/leer" \
        "/eigen/konten/lokal=$TMPD/eigenordner/konten/lokal" \
        > "$TMPD/mkfs.txt" 2>&1 || { tail -3 "$TMPD/mkfs.txt"; exit 1; }
fi

if [ "${NETZ:-1}" = "1" ]; then
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
    rm -f "$TMPD/protokoll.jsonl"
    ip netns exec "$NS" python3 tools/account/attrappe.py --port 8443 \
        --zertifikat "$TMPD/certs/good.pem" --schluessel "$TMPD/certs/good.key" \
        --verzeichnis "$TMPD" > "$TMPD/srv.log" 2>&1 & SRVPID=$!
    sleep 1.0
fi

# Ab hier: JEDES Argument ist EIN Gast-Lauf, nacheinander, gegen
# denselben laufenden Server. `@ZW@` in einem Skript wird durch das
# `zwischen`-Token des vorigen Laufs ersetzt -- damit laesst sich der
# zweite Faktor in einem Rutsch durchspielen.
ZW=""
if [ $# -eq 0 ]; then set -- "konto anbieter"; fi
for SKRIPT in "$@"; do
    SKRIPT=${SKRIPT//@ZW@/$ZW}
    echo "-- Gast: $SKRIPT"
    if [ "${NETZ:-1}" = "1" ]; then
        timeout 200 qemu-system-x86_64 -kernel "$K" -m 512 \
            -append "osum nokbd nosched noproc nofs noring3 nic nip=10.9.0.2/24 ngw=10.9.0.1 nsvc=0 nwait=0 script=$SKRIPT;exit" \
            -serial "file:$TMPD/out.txt" -display none -no-reboot \
            -drive "file=$TMPD/d.img,format=raw,if=ide,index=0" \
            -netdev "socket,id=n0,udp=127.0.0.1:$BPORT,localaddr=127.0.0.1:$QPORT" \
            -device "e1000,netdev=n0,mac=52:54:00:aa:bb:cc" \
            -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    else
        timeout 200 qemu-system-x86_64 -kernel "$K" -m 512 \
            -append "osum nokbd nosched noproc nofs noring3 script=$SKRIPT;exit" \
            -serial "file:$TMPD/out.txt" -display none -no-reboot \
            -drive "file=$TMPD/d.img,format=raw,if=ide,index=0" \
            -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    fi
    grep -aE '^konto:|user fault|too many|panic' "$TMPD/out.txt"
    Z=$(grep -aoE '^konto: zwischen = .*' "$TMPD/out.txt" | tail -1 | sed 's/^konto: zwischen = //')
    [ -n "$Z" ] && ZW="$Z"
done
echo "== Attrappe =="
tail -15 "$TMPD/srv.log" 2>/dev/null
echo "== Protokoll =="
tail -3 "$TMPD/protokoll.jsonl" 2>/dev/null
