#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${NETCHECK_SHOTS:-$(mktemp -d)}
mkdir -p "$OUT"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"; kill $(jobs -p) 2>/dev/null' EXIT
export DESIGNBUILD="$TMPD/build"
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps dhcp"
cat > "$TMPD/dreh.txt" <<EOF
warteauf 'taskbar: steht|taskbar: geom' || 120
warte ${NETCHECK_SETTLE:-90}
foto 00-bar
fahreauf netz
warte 3
foto 01-hover
klickauf chevron
warteauf 'traypop: open' || 25
warte 3
foto 02-flyout
EOF
VARIANTS=${NETCHECK_VARIANTS:-"ok:1: noinet:1:--no-inet noinet:2:--no-inet nogw:2:--no-echo usb:1: noicmp:1:--no-icmp"}
for v in $VARIANTS; do
    IFS=: read -r name scale flags <<< "$v"
    qp=$((20000 + RANDOM % 20000)); hp=$((40000 + RANDOM % 20000))
    python3 -I tools/pinggw/peer.py --local "$hp" --remote "$qp" --log "$TMPD/$name.peer" --secs 400 $flags &
    pp=$!
    sleep 1
    NIC="e1000,netdev=n0,mac=52:54:00:aa:bb:cc"
    EXTRA_WORDS=""
    if [ "$name" = usb ]; then NIC="usb-net,bus=x0.0,netdev=n0,mac=52:54:00:aa:bb:cc"; EXTRA_WORDS="usbpoll"; fi
    EH_APPEND="$EXTRA_WORDS" EH_NETDEV="-netdev socket,id=n0,udp=127.0.0.1:$hp,localaddr=127.0.0.1:$qp -device $NIC" \
    APPS="fetch netcheck" bash tools/design/eh6.sh "$TMPD/o-$name-$scale" res=1280x800 accel=kvm netz=ja uiscale="$scale" progs="$PROGS" \
        tbextra="tray_chevron=1" drehbuch="$TMPD/dreh.txt" > "$TMPD/o-$name-$scale.log" 2>&1 < /dev/null
    kill $pp 2>/dev/null
    mkdir -p "$OUT/$name-$scale"
    cp "$TMPD/o-$name-$scale"/*.ppm "$TMPD/o-$name-$scale/serial.txt" "$OUT/$name-$scale/" 2>/dev/null
    grep -a 'netcheck\|nethealth' "$TMPD/o-$name-$scale/serial.txt" | head -5
done
echo "SHOTS: $OUT"
