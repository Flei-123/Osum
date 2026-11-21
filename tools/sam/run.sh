#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/sam/run.sh -- Surface Aggregator driver against a fake embedded controller (QEMU pci-serial + tools/sam/ec.py).
#
# MEASURES: probe over a real 16550 PIO UART, firmware version request, HID descriptor transfer, event enable, keyboard
# and touchpad reports reaching hidin (counted in /proc/inputdiag), the compact `input:` boot lines.
# DOES NOT MEASURE: the LPSS UART clock, 4 Mbaud polling, the real EC.
# NEGATIVE CONTROLS: mute EC (no answers), corrupted event CRC (all events dropped), boot word `nosam`.
#
# Usage: bash tools/sam/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there" || ok "$3"; }
D=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$D"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
. tools/lib/firnenv.sh
finish() { [ -n "${SAM_KEEP:-}" ] && cp "$D"/*.klar "$SAM_KEEP"/ 2>/dev/null; echo "SAM: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }

echo "== 1. build =="
PROGS="sh cat echo sleep"
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; finish; }
if [ -n "${SAM_KERNEL:-}" ]; then
    cp "$SAM_KERNEL" "$D/k0.img"
    ok "kernel given"
else
    ./tools/build-kernel.sh "$D/k0.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; finish; }
fi
cat > "$D/s.sh" <<'EOS'
sleep 6
echo ==DIAG==
cat /proc/inputdiag
echo ==END==
EOS
bash tools/mkfsfi/mkfs.sh build "$D/d.img" 20000 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
    $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
    "/t/s.sh=$D/s.sh" > "$D/mkfs.txt" 2>&1 || tail -3 "$D/mkfs.txt"

runvm() { # name ec-mode words
    local name=$1 mode=$2 words=$3
    local sock="$D/ec-$name.sock"
    cp "$D/d.img" "$D/d-$name.img"
    python3 -I tools/sam/ec.py "$sock" "$mode" &
    local epid=$!
    local i=0
    while [ ! -S "$sock" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
    timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$D/k0.img" -m 512 \
        -chardev "socket,id=ec,path=$sock,server=off" -device pci-serial,chardev=ec \
        -vga std -append "osum vfs bus gfx wm wig desk wmshell wmdauer wigapp=/bin/sh,/t/s.sh wighalt=30 r3alle nokbd $words" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local qpid=$!
    local w=0
    while [ $w -lt 150 ] && kill -0 "$qpid" 2>/dev/null && ! grep -qa '==END==' "$D/o-$name.txt" 2>/dev/null; do sleep 1; w=$((w+1)); done
    kill "$qpid" 2>/dev/null
    wait "$qpid" 2>/dev/null
    kill "$epid" 2>/dev/null
    wait "$epid" 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}
field() { sed -n "s/.*$2=\([0-9a-fx]*\).*/\1/p" "$1" | head -1; }
diagline() { sed -n '/==DIAG==/,/==END==/p' "$D/$1.klar" | grep "^$2" | head -1; }

echo "== 2. fake EC, driver up =="
runvm ok ok "samsim"
has "$D/ok.klar" "sam: sam.state 6" "link up and devices set up (state 6)"
has "$D/ok.klar" "sam: sam.fw 0x00030007" "firmware version from the EC"
has "$D/ok.klar" "slot=" "device lines present"
has "$D/ok.klar" "input: ps2 present=" "boot line input: ps2"
has "$D/ok.klar" "input: sam state=6 present=1" "boot line input: sam up"
has "$D/ok.klar" "==DIAG==" "script ran"
SAMLINE=$(diagline ok "sam state")
echo "  INFO  $SAMLINE"
case "$SAMLINE" in "sam state=6 present=1"*) ok "inputdiag: sam state 6 present";; *) bad "inputdiag sam line: $SAMLINE";; esac
HID=$(diagline ok "hid keys")
KEYS=$(echo "$HID" | sed -n 's/.*keys=\([0-9]*\).*/\1/p')
MOVES=$(echo "$HID" | sed -n 's/.*moves=\([0-9]*\).*/\1/p')
echo "  INFO  $HID"
[ "${KEYS:-0}" -ge 3 ] && ok "keyboard events reach hidin (keys=$KEYS)" || bad "keyboard events: keys=${KEYS:-none}"
[ "${MOVES:-0}" -ge 3 ] && ok "touchpad reports reach hidin (moves=$MOVES)" || bad "touchpad reports: moves=${MOVES:-none}"

[ -n "${SAM_ONLY:-}" ] && finish
echo "== 3. negative controls =="
runvm mute mute "samsim"
has "$D/mute.klar" "sam: sam.state 4" "control mute EC: state 4 (no EC)"
hasnot "$D/mute.klar" "input: sam state=6" "control mute EC: not up"
runvm badev badevents "samsim"
has "$D/badev.klar" "sam: sam.state 6" "control corrupt events: link and setup still fine"
HID2=$(diagline badev "hid keys")
K2=$(echo "$HID2" | sed -n 's/.*keys=\([0-9]*\).*/\1/p')
[ "${K2:-1}" -eq 0 ] && ok "control corrupt events: keys=0" || bad "control corrupt events: keys=${K2:-none}"
runvm nosam ok "samsim nosam"
has "$D/nosam.klar" "sam: sam.state 2" "control nosam: disabled (state 2)"
hasnot "$D/nosam.klar" "sam.fw 0x00030007" "control nosam: EC never asked"
finish
