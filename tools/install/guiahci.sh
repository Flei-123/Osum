#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#   BAU=<dir with osum.mb + root.img> [DISK_MIB=476940] [GUI_NAME=admin] [GUI_PW=abcde] [PRESET=gpt|empty] bash tools/install/guiahci.sh [outdir]
set -uo pipefail
cd "$(dirname "$0")/../.."
export BOOT_KERNEL_COPY=1
. tools/lib/qemu.sh
OUT=${1:-/tmp/guiahci}
mkdir -p "$OUT"
BAU=${BAU:-}
DISK_MIB=${DISK_MIB:-476940}
GUI_NAME=${GUI_NAME:-admin}
GUI_PW=${GUI_PW:-abcde}
PRESET=${PRESET:-gpt}
OLD_DISK=${OLD_DISK:-}
INSTALL_WAIT=${INSTALL_WAIT:-2400}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
if [ -z "$BAU" ]; then
    BAU="$OUT/bau"
    bash tools/usbimg/build.sh "$BAU" > "$OUT/bau.log" 2>&1 || { echo "build failed"; tail -5 "$OUT/bau.log"; exit 1; }
fi
DISK="$OUT/target.img"
rm -f "$DISK"
if [ "$PRESET" = reinstall ]; then
    [ -f "$OLD_DISK" ] || { echo "OLD_DISK missing"; exit 1; }
    cp --sparse=always "$OLD_DISK" "$DISK"
else
    dd if=/dev/null of="$DISK" bs=1M seek="$DISK_MIB" 2> /dev/null
fi
if [ "$PRESET" = gpt ]; then
    sgdisk -o -n 1:2048:+96M -t 1:EF00 -c 1:ESP -n 2:0:0 -t 2:8300 -c 2:osroot "$DISK" > "$OUT/sgdisk.log" 2>&1
    mkfs.vfat -F 32 --offset 2048 "$DISK" 98304 > /dev/null 2>&1
    head -c 4194304 /dev/urandom | dd of="$DISK" bs=1M seek=100 conv=notrunc 2> /dev/null
fi
SER="$OUT/serial.txt"; SOCK="$OUT/mon.sock"; rm -f "$SER" "$SOCK"
APPEND="modfs osum vfs gfx wm wig wmhold wmdauer wighalt=3000 nosched noproc nofs lang=de uiscale=1 wigapp=/bin/installer"
timeout 3300 $QEMU_X86 -m 512 -kernel "$BAU/osum.mb" -initrd "$BAU/root.img" -append "$APPEND" \
    -serial "file:$SER" -display none -no-reboot \
    -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
    -monitor "unix:$SOCK,server,nowait" \
    -device ich9-ahci,id=ahci0 -drive "if=none,id=hd0,file=$DISK,format=raw" \
    -device ide-hd,drive=hd0,bus=ahci0.0 > "$OUT/qemu.log" 2>&1 &
QP=$!
trap 'kill $QP 2>/dev/null' EXIT
i=0
while [ $i -lt 600 ]; do
    grep -qa 'installer: ready' "$SER" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 0.5; i=$((i+1))
done
sleep 4
mon() { printf '%s\n' "$@" > "$OUT/m.txt"; python3 tools/wm/monitor.py "$SOCK" "$OUT/m.txt" > "$OUT/m.log" 2>&1; }
click() { python3 tools/themestore/click.py "$1" > "$OUT/c.txt"; python3 tools/wm/monitor.py "$SOCK" "$OUT/c.txt" > "$OUT/c.log" 2>&1; sleep 1; }
keys() { local k; for k in "$@"; do mon "sendkey $k"; sleep 0.35; done; sleep 1; }
typed() { local s=$1 i c; for ((i = 0; i < ${#s}; i++)); do c=${s:i:1}; keys "$c"; done; }
last() { grep -a 'installer: account ks=' "$SER" | tail -1 | sed 's/.*account //'; }
grep -aq 'installer: ready n=1' "$SER" && ok "installer window up, one disk" || { bad "no installer window"; tail -3 "$SER"; }
last_button() {
    grep -aoE "installer: rect id=[0-9]+ kind=2 x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+" "$SER" | tail -1 \
        | awk '{ split($5,a,"="); split($6,b,"="); split($7,c,"="); split($8,d,"="); printf "%d,%d", 42 + a[2] + c[2]/2, 62 + b[2] + d[2]/2 }'
}
nth_entry() {
    grep -aoE "installer: rect id=[0-9]+ kind=4 x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+" "$SER" | sed -n "${1}p" \
        | awk '{ split($5,a,"="); split($6,b,"="); split($7,c,"="); split($8,d,"="); printf "%d,%d", 42 + a[2] + c[2]/2, 62 + b[2] + d[2]/2 }'
}
F1=$(nth_entry 1); F2=$(nth_entry 2); F3=$(nth_entry 3)
click "$F1"; typed "$GUI_NAME"
click "$F2"; typed "$GUI_PW"
click "$F3"; typed "$GUI_PW"
[ "$(last)" = "ks=3 go=1" ] && ok "typed name '$GUI_NAME' + password: button on" || bad "state after typing: '$(last)'"
GO=$(last_button)
[ -n "$GO" ] && ok "install button at $GO" || bad "no install button rect"
click "$GO"
i=0
while [ $i -lt 60 ] && ! grep -qa 'installer: ask=1' "$SER"; do sleep 1; i=$((i+1)); done
keys ret
i=0
while [ $i -lt 60 ] && ! grep -qa 'installer: ask=2' "$SER"; do sleep 1; i=$((i+1)); done
keys ret
i=0
while [ $i -lt "$INSTALL_WAIT" ]; do
    grep -qa 'installer: done\|installer: ERROR' "$SER" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 1; i=$((i+1))
done
sleep 3
grep -a 'installer:' "$SER" | tail -8 | sed 's/^/        /'
EXPECT_REASON=${EXPECT_REASON:-}
if [ -n "$EXPECT_REASON" ]; then
    grep -qa "installer: reason=$EXPECT_REASON " "$SER" && ok "failure cause $EXPECT_REASON reported" || bad "failure cause $EXPECT_REASON missing"
    grep -qa 'installer: done' "$SER" && bad "installer finished although a failure was expected"
else
    grep -qa 'installer: done' "$SER" && ok "installer finished" || bad "installer did not finish"
    for n in 1 2 3 4 5; do
        grep -qa "installer: step=$n " "$SER" && ok "phase $n shown" || bad "phase $n missing"
    done
    grep -qa 'installer: reason=' "$SER" && bad "failure reason reported on success"
    sgdisk -v "$DISK" 2>&1 | grep -q 'No problems found' && ok "sgdisk -v: no problems" || bad "sgdisk -v complains"
fi
kill $QP 2>/dev/null; wait $QP 2>/dev/null
trap - EXIT
echo
echo "GUIAHCI: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
