#!/usr/bin/env bash
# ein einziger Lauf der Oberflaeche, zum Iterieren
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh >/dev/null 2>&1
export FIRNLIB="$(pwd)/lib"
D=${GD:-/root/vw/gd}; mkdir -p "$D"
[ "${SKIPK:-0}" = 1 ] || bash tools/build-kernel.sh "$D/k.mb" >/dev/null || exit 1
[ -f "$D/crt.o" ] || as --64 -o "$D/crt.o" kernel/user/crt.s
for p in viewer sh echo ls cat launcher explorer widgetdemo locate edit; do
    [ -f "$D/$p.elf" ] && [ "$p" != viewer ] && continue
    vendor/firn/bin/firnc "kernel/user/$p.fi" -o "$D/$p.o" > "$D/$p.err" 2>&1 || { echo "== $p"; head -5 "$D/$p.err"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start -o "$D/$p.elf" "$D/crt.o" "$D/$p.o" || exit 1
done
[ -d "$D/baum" ] || python3 tools/k15/tree.py "$D/baum" >/dev/null
[ -d "$D/fix" ] || python3 tools/viewer/mkbilder.py "$D/fix" >/dev/null
A=(build "$D/g.img" 8192 --inodes=128 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/)
for p in viewer sh echo ls cat launcher explorer widgetdemo locate edit; do A+=("/bin/$p=$D/$p.elf"); done
A+=(/etc/ "/etc/theme=$D/baum/theme" /bilder/
    "/bilder/a-rot.png=$D/fix/prgb.png" "/bilder/b-foto.jpg=$D/fix/j420.jpg"
    "/bilder/c-alpha.png=$D/fix/palpha.png" "/bilder/d-tier.gif=$D/fix/ganim.gif"
    "/bilder/e-wappen.bmp=$D/fix/b24.bmp" "/bilder/f-quer.jpg=$D/fix/jexif.jpg"
    "/bilder/g-gross.jpg=$D/fix/j12mp.jpg")
while read -r z; do A+=("$z"); done < <(python3 tools/k15/bundle.py assets/apps "$D/buendel")
python3 tools/osum/mkfs.py "${A[@]}" > "$D/mkfs.log" 2>&1 || { tail -3 "$D/mkfs.log"; exit 1; }
cp "$D/g.img" "$D/live.img"
M="$D/m.mon"; : > "$M"
if [ -n "${MONFILE:-}" ]; then cat "$MONFILE" >> "$M"
else printf 'warte 1.5\nsendkey tab\nwarte 0.6\nsendkey spc\nwarte 12.0\n' >> "$M"; fi
sock="$D/mon.sock"; rm -f "$sock" "$D/out.txt"
timeout 200 $QEMU_X86 -kernel "$D/k.mb" -m 384 \
    -append "gfx wm wigapp=/bin/viewer wmhold wiglong wigxl nokbd nosched noproc nofs" \
    -serial "file:$D/out.txt" -display none -no-reboot -vga std \
    -monitor "unix:$sock,server,nowait" \
    -drive "file=$D/live.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
pid=$!
i=0; while [ $i -lt 900 ]; do grep -qaE '^wm: hold' "$D/out.txt" 2>/dev/null && break; kill -0 $pid 2>/dev/null || break; sleep 0.15; i=$((i+1)); done
python3 tools/wm/monitor.py "$sock" "$M" > "$D/monlog" 2>&1
python3 tools/gfx/screenshot.py "$sock" "$D/s.ppm" 25 > "$D/shot" 2>&1
wait $pid; echo "rc=$?"
grep -a 'viewer: spur\|viewer: taste\|viewer: an=\|fault' "$D/out.txt" | tail -12
