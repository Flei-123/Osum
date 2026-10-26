#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/marke-env.sh"
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
T=$(mktemp -d)
IMG=${TASKBARMEM_IMG:-}
OLD=${TASKBARMEM_OLD_IMG:-}
OUTDIR=${TASKBARMEM_OUT:-}
trap 'bash "$ROOT/tools/odbc/qemu.sh" stop "$T" >/dev/null 2>&1; rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
if [ -z "$IMG" ]; then
    mkdir -p "$T/img"
    ODB=1 IMAGE_ID=taskbarmem bash tools/usbimg/build.sh "$T/img" > "$T/build.log" 2>&1 || { tail -5 "$T/build.log"; echo "image build failed"; exit 1; }
    IMG="$T/img/${MARKE_DATEI}-usb.img"
    OUTDIR="$T/img"
fi
O="python3 -I tools/odbc/odbc.py --port unix:$T/odb.sock --token-file ${ODB_TOKEN_FILE:-/root/abbilder/odb.token}"

desktop_copy() {
    cp --reflink=auto "$1" "$T/disk.img"
    mcopy -n -i "$T/disk.img@@1M" ::limine.conf "$T/limine.conf" || return 1
    sed -i 's/ anmeldung//' "$T/limine.conf"
    mcopy -D o -i "$T/disk.img@@1M" "$T/limine.conf" ::limine.conf
}

measure() {
    desktop_copy "$1" || { echo "image copy failed"; return 1; }
    QEMU_DRIVE=ahci bash tools/odbc/qemu.sh start "$T/disk.img" "$T" 2 1536 >/dev/null || { echo "qemu start failed"; return 1; }
    timeout 240 $O wait 200 >/dev/null || { echo "agent never answered"; return 1; }
    sleep 40
    PID=$(timeout 30 $O exec /bin/ps | awk '$NF=="taskbar" {print $1; exit}')
    [ -n "$PID" ] || return 1
    timeout 30 $O exec /bin/cat /proc/$PID/mmaplog > "$T/log0.txt"
    A=$(awk '$1=="m" {n+=$6} END {print n+0}' "$T/log0.txt")
    sleep 45
    timeout 30 $O exec /bin/cat /proc/$PID/mmaplog > "$T/log1.txt"
    B=$(awk '$1=="m" {n+=$6} END {print n+0}' "$T/log1.txt")
    KB=$(timeout 30 $O exec /bin/grep VmRSS /proc/$PID/status | awk '{print $2}')
    GROWTH=$((B - A))
    bash tools/odbc/qemu.sh stop "$T" >/dev/null 2>&1
    return 0
}

echo "== 1. analyzer =="
python3 -I tools/taskbarmem/analyze.py --selftest > "$T/st.txt" 2>&1 && ok "analyze.py selftest" || { bad "analyze.py selftest"; cat "$T/st.txt"; }
echo "== 2. desktop, idle =="
if measure "$IMG"; then
    ROWS=$(grep -c '^[mu] ' "$T/log1.txt")
    [ "$ROWS" -ge 3 ] && ok "mmaplog lists allocation sites ($ROWS rows)" || bad "mmaplog empty ($ROWS rows)"
    [ "$GROWTH" -le 20 ] && ok "taskbar mmap calls in 45 s idle: $GROWTH (limit 20)" || bad "taskbar keeps mapping memory: $GROWTH calls in 45 s"
    [ "${KB:-999999}" -le 61440 ] && ok "taskbar VmRSS $KB kB (limit 61440)" || bad "taskbar VmRSS $KB kB"
    python3 -I tools/taskbarmem/analyze.py "$T/log1.txt" --min-count 100 --fail-on-leak > "$T/an.txt" 2>&1 && ok "analyzer: no leak rows" || { bad "analyzer flags leak rows"; head -5 "$T/an.txt"; }
else
    bad "measurement failed"
fi
if [ -n "$OLD" ]; then
    echo "== 3. counter-proof: pre-fix image must leak =="
    if measure "$OLD"; then
        [ "$GROWTH" -gt 100 ] && ok "pre-fix image leaks: $GROWTH mmap calls in 45 s" || bad "counter-proof: pre-fix image did not leak ($GROWTH)"
        python3 -I tools/taskbarmem/analyze.py "$T/log1.txt" --min-count 100 --fail-on-leak > "$T/an.txt" 2>&1 && bad "counter-proof: analyzer did not flag the pre-fix log" || ok "counter-proof: analyzer flags the pre-fix log"
    else
        bad "counter-proof measurement failed"
    fi
fi
echo "taskbarmem: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
