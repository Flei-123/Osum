#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
mkdir -p "$OUT"
export DESIGNBUILD="${DESIGNBUILD:-$OUT/build}"
export AUDIT_TIMEOUT="${AUDIT_TIMEOUT:-900}"
HALT_SECONDS=100
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

run_case() {
    local name=$1 scale=$2 res=$3 kbd=$4
    local dir="$OUT/$name" dreh="$OUT/$name.txt"
    mkdir -p "$dir"
    {
        echo "warteauf 'launcher: ready' || 240"
        echo "warte 8"
        echo "tippe echo AUDITSHELL_OK"
        echo "taste ret"
        echo "warte 10"
        echo "foto shell"
    } > "$dreh"
    bash tools/design/audit.sh "$dir" accel=kvm uitrace=yes kbd="$kbd" uiscale="$scale" res="$res" \
        extra=termdump halt=$HALT_SECONDS drehbuch="$dreh" > "$OUT/$name.audit.log" 2>&1
}

run_case live1 1 1280x800 on &
run_case live2 2 1920x1080 on &
run_case dead1 1 1280x800 off &
wait

judge() {
    local name=$1 expect=$2 label=$3 line
    if line=$(python3 -I tools/auditshell/check.py "$OUT/$name/serial.txt" "$expect" 2>&1); then
        ok "$label: $line"
    else
        bad "$label: $line"
    fi
}

judge live1 alive "console shell answers a typed command, scale 1"
judge live2 alive "console shell answers a typed command, scale 2"
judge dead1 dead "counter-probe: without kbd=on the shell reads EOF and says bye"
echo "AUDITSHELL: $pass passed, $fail failed"
[ "$fail" = 0 ]
