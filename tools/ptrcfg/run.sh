#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# tools/ptrcfg/run.sh -- gate for L-001 (pointer speed, acceleration curve,
# natural scrolling; kernel/drv/hid/ptrcfg.fi).
#
# 1. build the kernel (stage 0)
# 2. boot it headless with the window manager word; the kernel prints one
#    `ptrcfg: case ...` line per curve case and one `ptrcfg: e2e ...` line
#    for a real packet through ps2m.usb_packet/apply
# 3. compare every line with the independent Python reference
#    (tools/ptrcfg/ref.py)
# 4. the settings schema carries mouse.speed / mouse.accel / mouse.natural
#    with `store /etc/mouse.conf`
# 5. counter-probe: the reference must differ between flat and accelerated
#    (a curve that is the identity everywhere would pass step 3 too)
#
# Usage: bash tools/ptrcfg/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$*"; }
bad() { fail=$((fail+1)); printf '  NEIN %s\n' "$*"; }

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "PTRCFG: skipped, no qemu"; exit 0
fi

echo "== 1. reference =="
python3 tools/ptrcfg/ref.py > "$TMPD/ref.txt" || { bad "ref.py fails"; exit 1; }
n=$(wc -l < "$TMPD/ref.txt")
[ "$n" -ge 9 ] && ok "reference prints $n lines" || bad "reference prints only $n lines"
c0=$(grep -a 'case 0 ' "$TMPD/ref.txt" | sed 's/.*x=\([-0-9]*\) y=.*/\1/')
c3=$(grep -a 'case 3 ' "$TMPD/ref.txt" | sed 's/.*x=\([-0-9]*\) y=.*/\1/')
[ "$c0" != "$c3" ] && ok "counter-probe: accel 2 differs from flat ($c0 vs $c3)" \
    || bad "counter-probe: accel changes nothing"

echo "== 2. schema =="
for k in mouse.speed mouse.accel mouse.natural; do
    grep -q "^setting $k " etc/settings.schema && ok "$k in settings.schema" || bad "$k missing"
done
[ "$(grep -c 'store /etc/mouse.conf' etc/settings.schema)" = 3 ] \
    && ok "three keys stored in /etc/mouse.conf" || bad "store lines wrong"

echo "== 3. kernel =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
KMB="${PTRCFG_KERNEL:-$TMPD/k.mb}"
if [ ! -s "$KMB" ]; then
    bash tools/build-kernel.sh "$KMB" --stufe 0 > "$TMPD/b.log" 2>&1 \
        && ok "kernel builds" || { bad "kernel build fails"; tail -8 "$TMPD/b.log"; exit 1; }
fi
python3 tools/osum/mkfs.py build "$TMPD/disk.img" 4096 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf \
    > "$TMPD/mkfs.txt" 2>&1 && ok "font disk built" || bad "mkfs.py fails"
timeout 120 $QEMU_X86 -kernel "$KMB" -m 256 \
    -append "gfx wm nokbd nosched noproc nofs fbres=800x600" \
    -serial "file:$TMPD/serial.txt" -display none -no-reboot \
    -vga std -global VGA.edid=off \
    -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
grep -a '^ptrcfg: ' "$TMPD/serial.txt" | sed 's/\r//' > "$TMPD/got.txt"
ng=$(wc -l < "$TMPD/got.txt")
[ "$ng" = "$n" ] && ok "kernel printed $ng ptrcfg lines" || bad "kernel printed $ng lines, expected $n"
i=0
while IFS= read -r want; do
    i=$((i+1))
    got=$(sed -n "${i}p" "$TMPD/got.txt")
    [ "$got" = "$want" ] && ok "$want" || bad "got '$got' expected '$want'"
done < "$TMPD/ref.txt"

echo "PTRCFG: $pass ok / $fail fail"
[ "$fail" = 0 ]
