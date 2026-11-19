#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/photostream/desktop.sh -- jarvisd JPEG photo job on the REAL desktop of an ODB=1 full image in QEMU:
# stage times per width, dirty check (unchanged screen answers 'S', changed screen answers 'J'), frames per second.
#
#   bash tools/photostream/desktop.sh --image <xoffios-usb.img of an ODB=1 build> [--smp 2] [--token-file F]
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
IMG=""; SMP=2; TOKEN=/root/abbilder/odb.token
while [ $# -gt 0 ]; do
    case $1 in
        --image) IMG=$2; shift 2 ;;
        --smp) SMP=$2; shift 2 ;;
        --token-file) TOKEN=$2; shift 2 ;;
        *) echo "unknown option $1"; exit 2 ;;
    esac
done
[ -f "$IMG" ] || { echo "desktop.sh: --image required"; exit 2; }
D=$(mktemp -d)
cleanup() { bash "$ROOT/tools/odbc/qemu.sh" stop "$D" >/dev/null 2>&1; rm -rf "$D"; }
trap cleanup EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
cp --reflink=auto "$IMG" "$D/disk.img" || exit 2
bash "$ROOT/tools/odbc/qemu.sh" start "$D/disk.img" "$D" "$SMP" 1536 > /dev/null || exit 1
ODBC=(python3 -I "$ROOT/tools/odbc/odbc.py" --port "unix:$D/odb.sock" --token-file "$TOKEN")
"${ODBC[@]}" wait 240 > /dev/null || { bad "agent never answered"; exit 1; }
"${ODBC[@]}" input text startkennwort > /dev/null
"${ODBC[@]}" input key Enter > /dev/null
for _ in $(seq 1 60); do
    "${ODBC[@]}" exec ps 2>/dev/null | grep -q taskbar && break
    sleep 2
done
sleep 8
"${ODBC[@]}" exec ps 2>/dev/null | grep -q taskbar && ok "desktop up" || { bad "desktop not up"; exit 1; }
"${ODBC[@]}" push "$ROOT/assets/jarvis/rechte-hp.conf" /etc/jarvis/permissions.conf > /dev/null 2>&1 && ok "permissions with screenshot = yes pushed" || bad "permissions push failed"
ctl() { "${ODBC[@]}" exec "/bin/jarvisctl screenshot 600" 2>&1 | sed "s/^/ctl: /" >&2; }
photo() { ctl; "${ODBC[@]}" exec "/bin/jarvisd -j /tmp/p$1.jpg $2" 2>&1; }
logline() { grep -a 'photo' <<< "$1" | head -1; }
field() { sed -n "s/.* $1=\([0-9x]*\).*/\1/p" <<< "$2"; }
ctl
t0=$(date +%s.%N)
"${ODBC[@]}" exec "/bin/jarvisd -f /tmp/p.png" > /dev/null 2>&1
t1=$(date +%s.%N)
png_bytes=$("${ODBC[@]}" exec "/bin/ls -l /tmp/p.png" 2>/dev/null | tr -s ' ' | tr '\n' ' ')
ok "PNG path wall time incl. exec overhead: $(python3 -c "print(round(float('$t1')-float('$t0'),2))") s ($png_bytes)"
for w in 1280 960 800 640; do
    out=$(photo "$w" "q=55,w=$w"); l=$(logline "$out")
    [ -n "$l" ] && ok "w=$w: size $(field size "$l"), $(field bytes "$l") bytes, grab $(field grab "$l") ms, scale $(field scale "$l") ms, encode $(field encode "$l") ms" || bad "w=$w: no photo line ($out)"
done
"${ODBC[@]}" input key Tab > /dev/null 2>&1
sleep 3
settled=""
for attempt in 1 2 3 4 5 6; do
    out=$(photo base "b=1,t=1200,w=800")
    grep -a 'photo' <<< "$out" | head -1 | sed "s/^/  attempt $attempt: /"
    if grep -aq 'unchanged' <<< "$out"; then settled=$attempt; break; fi
    sleep 5
done
[ -n "$settled" ] && ok "idle desktop: dirty check answers unchanged (attempt $settled)" || bad "idle desktop never settled"
( sleep 3; "${ODBC[@]}" input mouse 150 718 --button left --action click > /dev/null 2>&1 ) &
out=$(photo chg "b=1,t=9000,w=800"); wait
grep -aq 'unchanged' <<< "$out" && bad "screen change not noticed (click on a button)" || ok "screen change noticed within 9 s"
echo "PHOTOSTREAM-DESKTOP: $pass passed, $fail failed"
[ "$fail" = 0 ]
