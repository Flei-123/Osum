#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/netview/smoke.sh -- ONE graphical boot, one Super+A, one picture.
# Not the acceptance: the fast loop while the panel is being built.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
TMPD=${SMOKED:-$(mktemp -d)}
mkdir -p "$TMPD"
echo "workdir $TMPD"

GPROGS="schreibtisch leiste einstellungen launcher explorer widgetdemo locate netview edit sh echo ls cat ps"
MONO=assets/osum-mono.ttf
SANS=assets/osum-sans.ttf
GBASE="gfx wm wig desk wmhold wiglong nokbd nosched noproc nofs"

if [ ! -s "$TMPD/k0.mb" ] || [ -n "${REBUILD:-}" ]; then
    bash tools/build-kernel.sh "$TMPD/k0.mb" --stufe 0 > "$TMPD/k.log" 2>&1 \
        || { echo "KERNEL FAILED"; tail -15 "$TMPD/k.log"; exit 1; }
fi
as --64 -o "$TMPD/crt.o" kernel/user/crt.s || exit 1
for pgm in $GPROGS; do
    "$FIRNC" "kernel/user/$pgm.fi" -o "$TMPD/g$pgm.o" > "$TMPD/ge$pgm" 2>&1 \
        && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
            -o "$TMPD/g$pgm.elf" "$TMPD/crt.o" "$TMPD/g$pgm.o" 2>/dev/null \
        && strip --strip-all "$TMPD/g$pgm.elf" \
        || { echo "BUILD FAILED: $pgm"; head -8 "$TMPD/ge$pgm"; exit 1; }
done
echo "userland built"

python3 tools/netview/icons.py bauen "$TMPD/icons" > /dev/null 2>&1 || exit 1
python3 tools/k15/tree.py "$TMPD/baum" > /dev/null 2>&1 || exit 1
printf '# taskbar.conf\nedge=%s\nheight=28\nwidth=104\nautohide=0\nontop=1\n' \
    "${EDGE:-bottom}" > "$TMPD/taskbar.conf"

ARGS=(build "$TMPD/d.img" 4096 /lib/
    "/lib/mono.ttf=$MONO" "/lib/sans.ttf=$SANS" /bin/)
for q in $GPROGS; do ARGS+=("/bin/$q=$TMPD/g$q.elf"); done
ARGS+=("/bin/files@/bin/explorer")
ARGS+=(/etc/ "/etc/theme=assets/netview/theme-dark" "/etc/taskbar.conf=$TMPD/taskbar.conf")
ARGS+=(/etc/netview/)
for q in state-nocarrier state-noip state-noroute state-online \
         mark-filtered mark-faked mark-none sys-faking \
         tile-fake tile-net tile-hide; do
    ARGS+=("/etc/netview/$q=$TMPD/icons/$q")
done
while read -r z; do ARGS+=("$z"); done < <(python3 tools/k15/bundle.py assets/apps "$TMPD/buendel")
while read -r z; do ARGS+=("$z"); done < "$TMPD/baum/liste"
python3 tools/osum/mkfs.py "${ARGS[@]}" > "$TMPD/mkfs.txt" 2>&1 || { tail -5 "$TMPD/mkfs.txt"; exit 1; }
cp -f "$TMPD/d.img" "$TMPD/l.img"

printf 'warte 5\nsendkey a\nwarte 2\nsendkey meta_l-a\nwarte 3\n' > "$TMPD/drive"
[ -n "${DRIVE:-}" ] && cp "$DRIVE" "$TMPD/drive"

rm -f "$TMPD/out.txt" "$TMPD/s.ppm" "$TMPD/mon.sock"
timeout 200 $QEMU_X86 -kernel "$TMPD/k0.mb" -m 256 \
    -append "$GBASE netvdemo" -serial "file:$TMPD/out.txt" -display none -no-reboot \
    -vga std -monitor "unix:$TMPD/mon.sock,server,nowait" \
    -drive "file=$TMPD/l.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/qemu.txt" 2>&1 &
pid=$!
i=0
while [ $i -lt 1200 ]; do
    grep -qaE '^wm: hold' "$TMPD/out.txt" 2>/dev/null && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.15; i=$((i+1))
done
python3 tools/wm/monitor.py "$TMPD/mon.sock" "$TMPD/drive" 0.12 > "$TMPD/mon.log" 2>&1
sleep 2
python3 tools/gfx/screenshot.py "$TMPD/mon.sock" "$TMPD/s.ppm" 30 > "$TMPD/shot.txt" 2>&1
kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null

echo "=========== what the machine said ==========="
grep -aE '^hk:|^qs:|^key: a$|^taskbar: work|^taskbar: geom|no quick' "$TMPD/out.txt" | head -40
echo "=========== picture ==========="
ls -la "$TMPD/s.ppm" 2>/dev/null
[ -s "$TMPD/s.ppm" ] && python3 -c "
import sys
from PIL import Image
Image.open('$TMPD/s.ppm').save('$TMPD/s.png')
print('png written')
"
