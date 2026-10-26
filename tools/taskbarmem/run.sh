#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
T=$(mktemp -d)
IMG=${TASKBARMEM_IMG:-}
trap 'bash "$ROOT/tools/odbc/qemu.sh" stop "$T" >/dev/null 2>&1; rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
if [ -z "$IMG" ]; then
    mkdir -p "$T/img"
    ODB=1 IMAGE_ID=taskbarmem bash tools/usbimg/build.sh "$T/img" > "$T/build.log" 2>&1 || { tail -5 "$T/build.log"; echo "image build failed"; exit 1; }
    IMG="$T/img/orientos-usb.img"
fi
cp --reflink=auto "$IMG" "$T/disk.img"
QEMU_DRIVE=ahci bash tools/odbc/qemu.sh start "$T/disk.img" "$T" 2 1536 >/dev/null || { echo "qemu start failed"; exit 1; }
O="python3 -I tools/odbc/odbc.py --port unix:$T/odb.sock --token-file ${ODB_TOKEN_FILE:-/root/abbilder/odb.token}"
timeout 240 $O wait 200 >/dev/null || { echo "agent never answered"; exit 1; }
sleep 20
PID=$(timeout 30 $O exec /bin/ps | awk '$NF=="taskbar" {print $1; exit}')
[ -n "$PID" ] && ok "taskbar pid found ($PID)" || { bad "taskbar not running"; exit 1; }
sum() { timeout 30 $O exec /bin/cat /proc/$1/mmaplog | awk '$1=="m" {n+=$6} END {print n+0}'; }
rows() { timeout 30 $O exec /bin/cat /proc/$1/mmaplog | grep -c '^[mu] '; }
R=$(rows "$PID")
[ "$R" -ge 3 ] && ok "mmaplog lists allocation sites ($R rows)" || bad "mmaplog empty ($R rows)"
A=$(sum "$PID"); sleep 60; B=$(sum "$PID")
[ $((B - A)) -le 20 ] && ok "taskbar mmap calls in 60 s idle: $((B - A)) (limit 20)" || bad "taskbar keeps mapping memory: $((B - A)) calls in 60 s"
KB=$(timeout 30 $O exec /bin/grep VmRSS /proc/$PID/status | awk '{print $2}')
[ "${KB:-999999}" -le 30720 ] && ok "taskbar VmRSS $KB kB (limit 30720)" || bad "taskbar VmRSS $KB kB"
Z=$(timeout 30 $O exec /bin/cat /proc/999/mmaplog 2>&1 | grep -c '^[mu] ')
[ "$Z" -eq 0 ] && ok "control: unused pid has no rows" || bad "control: unused pid shows rows"
echo "taskbarmem: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
