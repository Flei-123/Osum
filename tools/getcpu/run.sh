#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/summary.sh
summary_begin GETCPU
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
CORES=4
WORKERS=8
SAMPLES=${GETCPU_SAMPLES:-200}
MIN_DISTINCT=3
ACCEL=${GETCPU_ACCEL:-$([ -e /dev/kvm ] && echo kvm || echo tcg)}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d)
trap 'summary_guard; rm -rf "$D"' EXIT
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
PROGS="sh echo sleep cpuprobe"
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs build"; head -10 "$D/b.txt"; summary_emit "$pass" "$fail" 1; exit $?; }
./tools/build-kernel.sh "$D/k0.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel build"; tail -8 "$D/k.txt"; summary_emit "$pass" "$fail" 2; exit $?; }
{
    echo "sleep 1"
    for _ in $(seq "$WORKERS"); do echo "cpuprobe $SAMPLES &"; done
    echo "sleep 1"
    echo "echo ==WAIT=="
    echo "sleep 20"
    echo "echo ==END=="
} > "$D/s.sh"
bash tools/mkfsfi/mkfs.sh build "$D/d.img" 20000 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
    $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
    "/t/s.sh=$D/s.sh" > "$D/mkfs.txt" 2>&1 || tail -3 "$D/mkfs.txt"
runvm() {
    local name=$1 cores=$2 words=$3
    cp "$D/d.img" "$D/d-$name.img"
    timeout 240 qemu-system-x86_64 -accel "$ACCEL" -machine q35 -cpu Skylake-Client -smp "$cores" -kernel "$D/k0.img" -m 1024 \
        -append "osum vfs smpfrueh $words script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.log"
}
popcount() {
    local v=$1 n=0
    while [ "$v" -gt 0 ]; do n=$((n + (v & 1))); v=$((v >> 1)); done
    echo "$n"
}
analyze() {
    local log=$1 lines=0 union=0 highest=0 mask max
    while read -r mask max; do
        lines=$((lines+1)); union=$((union | mask))
        [ "$max" -gt "$highest" ] && highest=$max
    done < <(grep -a '^cpuprobe samples=' "$log" | sed -E 's/.* mask=([0-9]+) max=([0-9]+).*/\1 \2/')
    echo "$lines $union $highest $(popcount "$union")"
}
runvm base "$CORES" ""
grep -qa "==END==" "$D/base.log" && ok "base: script finished" || { bad "base: script did not finish"; tail -5 "$D/base.log"; }
read -r lines union highest distinct < <(analyze "$D/base.log")
echo "  info  base: lines=$lines union=$union highest=$highest distinct=$distinct"
[ "$lines" -eq "$WORKERS" ] && ok "base: $lines of $WORKERS workers reported" || bad "base: $lines of $WORKERS workers reported"
[ "$highest" -lt "$CORES" ] && ok "base: every value < $CORES (highest $highest)" || bad "base: value $highest >= $CORES"
[ "$distinct" -ge "$MIN_DISTINCT" ] && ok "base: $distinct distinct CPUs seen under load (>= $MIN_DISTINCT)" || bad "base: only $distinct distinct CPUs"
runvm nosmp 1 "nosmp"
grep -qa "==END==" "$D/nosmp.log" && ok "nosmp: script finished" || bad "nosmp: script did not finish"
read -r lines union highest distinct < <(analyze "$D/nosmp.log")
echo "  info  nosmp: lines=$lines union=$union highest=$highest distinct=$distinct"
[ "$lines" -eq "$WORKERS" ] && ok "nosmp: $lines of $WORKERS workers reported" || bad "nosmp: $lines of $WORKERS workers reported"
[ "$highest" -eq 0 ] && [ "$distinct" -eq 1 ] && ok "nosmp counter-proof: only CPU 0 seen (the multi-core check can fail)" || bad "nosmp counter-proof: highest $highest distinct $distinct, check not discriminating"
summary_emit "$pass" "$fail" 8
