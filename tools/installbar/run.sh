#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/installbar/run.sh -- installer progress bar gate (r2043): frames during a relocating shrink,
# the bar fill grows monotonically to full width; counter-check: a frame without the shrink has no bar.
# Run under heavy: /root/jarvis/bin/heavy bash tools/installbar/run.sh   (BAU=<usbimg build dir> reuses a build)
set -uo pipefail
cd "$(dirname "$0")/../.."
export BOOT_KERNEL_COPY=1
. tools/lib/qemu.sh
for t in sgdisk mkntfs ntfscp mkfs.vfat python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "INSTALLBAR: $t missing"; exit 1; }
done
OUT=$(mktemp -d); QP=""
trap 'kill $QP 2>/dev/null; rm -rf "$OUT"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
BAU=${BAU:-}
if [ -z "$BAU" ]; then
    BAU="$OUT/bau"
    bash tools/usbimg/build.sh "$BAU" > "$OUT/bau.log" 2>&1 || { echo "build failed"; tail -n 5 "$OUT/bau.log"; exit 1; }
fi
mkdir -p "$OUT/disk" "$OUT/frames"
bash tools/installbar/mkdisk.sh "$OUT/disk" && ok "foreign disk with data behind the shrink target" || { bad "foreign disk"; echo "INSTALLBAR: $pass passed, $fail failed"; exit 1; }
SER="$OUT/serial.txt"; SOCK="$OUT/mon.sock"
timeout 1500 $QEMU_X86 -m 512 -kernel "$BAU/osum.mb" -initrd "$BAU/root.img" \
    -append "modfs osum vfs gfx wm wig wmhold wmdauer wighalt=1400 nosched noproc nofs lang=de uiscale=1 wigapp=/bin/installer,now,beside" \
    -serial "file:$SER" -display none -no-reboot \
    -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$OUT/disk/disk.img,format=raw,if=ide,index=0,throttling.iops-total=${IOPS:-600}" > "$OUT/qemu.log" 2>&1 &
QP=$!
i=0
while [ $i -lt 600 ]; do
    grep -qa 'installer: ready' "$SER" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 0.5; i=$((i + 1))
done
grep -qa 'installer: ready' "$SER" && ok "installer window is up" || bad "installer window is not up"
n=0
while [ $n -lt 400 ]; do
    kill -0 "$QP" 2>/dev/null || break
    printf 'screendump %s/frames/f%03d.ppm\n' "$OUT" "$n" | socat - "UNIX-CONNECT:$SOCK" > /dev/null 2>&1
    n=$((n + 1))
    tr -d '\000' < "$SER" 2>/dev/null | grep -aq 'installer: shprog=100' && { [ -n "${DONE_AT:-}" ] || DONE_AT=$n; [ $n -ge $((DONE_AT + 2)) ] && break; }
    grep -aq 'installer: done\|installer: ERROR' "$SER" 2>/dev/null && break
    sleep 0.5
done
kill $QP 2>/dev/null; wait $QP 2>/dev/null
tr -d '\000' < "$SER" | grep -a '^installer: sh' | head -n 12 | sed 's/^/        /'
python3 -I tools/installbar/check.py "$OUT/frames" > "$OUT/check.txt" 2>&1
sed 's/^/        /' "$OUT/check.txt" | head -n 30
while IFS= read -r line; do
    case "$line" in
        OK\ *) ok "${line#OK }" ;;
        FAIL\ *) bad "${line#FAIL }" ;;
    esac
done < "$OUT/check.txt"
echo "INSTALLBAR: $pass passed, $fail failed"
[ "$fail" = 0 ]
