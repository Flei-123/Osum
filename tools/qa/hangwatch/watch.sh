#!/usr/bin/env bash
set -u
OUT=${1:?outdir}
PORT=${2:?gdb port}
ELF=${3:?kernel elf}
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
SAMPLES=${HANG_SAMPLES:-8}
SAMPLE_GAP=${HANG_SAMPLE_GAP:-1}
POLL_LIMIT=${HANG_WATCH_LIMIT:-900}
SETTLE=${HANG_SETTLE:-2}
KEEP_ALIVE=${HANG_KEEP:-1500}

dump() {
    HANG_REPO=$REPO HANG_ELF=$ELF HANG_PORT=$PORT HANG_MODE=$1 timeout 120 gdb -batch -nx -x "$HERE/hangdump.py" 2>&1
}

capture() {
    sleep "$SETTLE"
    dump full > "$OUT/hang-gdb.txt"
    local n=1
    while [ "$n" -le "$SAMPLES" ]; do
        sleep "$SAMPLE_GAP"
        { echo "SAMPLE $n"; dump quick; } >> "$OUT/hang-gdb.txt"
        n=$((n + 1))
    done
    echo "$PORT" > "$OUT/gdb-port"
    local held=0
    while [ "$held" -lt "$KEEP_ALIVE" ] && [ ! -e "$OUT/RELEASE" ]; do
        sleep 5
        held=$((held + 5))
    done
    printf 'quit\n' | socat - "UNIX-CONNECT:$OUT/mon.sock" > /dev/null 2>&1
}

i=0
while [ "$i" -lt "$POLL_LIMIT" ]; do
    if grep -qa '^FX-HANG kind=' "$OUT/ser.txt" 2>/dev/null; then
        capture
        exit 0
    fi
    if grep -qa '^FX-END' "$OUT/ser.txt" 2>/dev/null; then
        exit 0
    fi
    sleep 1
    i=$((i + 1))
done
