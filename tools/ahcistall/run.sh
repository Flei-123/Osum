#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${WD:-/root/fxhp}
STALL_S=${STALL_S:-20}
STALL_BPS=${STALL_BPS:-10000}
TMO=${TMO:-150}
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }

stalled_boot() {
    local kernel=$1 out=$2
    mkdir -p "$out"
    KERNEL=$kernel DRIVE=ahci SPEC=$WD/fxrun/spec.txt BLOCKS=1000000 TMO=$TMO \
        bash tools/linuxapps/run.sh "$WD" tools/ahcistall/guest.sh "$out" > "$out.log" 2>&1 &
    local runner=$!
    while [ ! -S "$out/mon.sock" ]; do sleep 0.2; done
    while ! grep -qa "mb:" "$out/ser.txt" 2>/dev/null; do sleep 0.1; done
    printf 'block_set_io_throttle d0 %s 0 0 0 0 0\n' "$STALL_BPS" | socat - "UNIX-CONNECT:$out/mon.sock" > /dev/null
    sleep "$STALL_S"
    printf 'block_set_io_throttle d0 0 0 0 0 0 0\n' | socat - "UNIX-CONNECT:$out/mon.sock" > /dev/null
    wait "$runner"
    grep -qa "AHCISTALL start" "$out/ser.clean" 2>/dev/null
}

if [ -n "${KERNEL:-}" ]; then
    KMB=$KERNEL
else
    KMB=$D/k.img
    bash tools/build-kernel.sh "$KMB" --stufe 0 > "$D/k.log" 2>&1 || { echo "AHCISTALL: kernel build failed"; tail -8 "$D/k.log"; exit 1; }
fi

if stalled_boot "$KMB" "$D/new"; then ok "init runs the sysinit script after a ${STALL_S} s host IO stall"; else bad "boot hangs after a ${STALL_S} s host IO stall"; fi
if grep -qa "FX-END" "$D/new/ser.clean"; then ok "guest reaches the end marker"; else bad "guest did not reach the end marker"; fi
if [ -n "${OLDK:-}" ]; then
    if stalled_boot "$OLDK" "$D/old"; then bad "counter-probe: old kernel survived the stall"; else ok "counter-probe: old kernel hangs after the stall"; fi
fi
echo "AHCISTALL: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
