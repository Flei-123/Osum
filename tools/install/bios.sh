#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/install/bios.sh -- r309: an INSTALLED disk boots through Legacy BIOS (SeaBIOS)
# AND through UEFI (OVMF), without the stick.
#
#   bash tools/install/bios.sh <image-dir> [work-dir]
#
# <image-dir> is the output of tools/usbimg/build.sh (osum.mb + root.img, and
# since r309 /boot/limine-hdd.bin + /boot/limine-bios.sys inside root.img).
#
# 1. install onto an empty 256 MiB disk with the real /bin/installer (as abnahme.sh)
# 2. the HOST reads the disk with foreign tools: sgdisk -v (both GPT copies valid,
#    CRC32s), the protective MBR has boot code and 0x55AA, limine-bios.sys is on
#    the EFI partition, stage 2 sits in the tail of both entry arrays
# 3. boot the disk with SeaBIOS (qemu -machine pc, no pflash) and with OVMF:
#    the sign-in screen must come up from the DISK (serial: rootpart=, a photo)
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
BAU=${1:?image dir}; W=${2:-/tmp/bios-run}
mkdir -p "$W"; rm -f "$W"/*.txt "$W"/*.png "$W"/*.ppm
ok=0; bad=0
okk() { ok=$((ok+1)); printf '  [ ok ] %s\n' "$*"; }
bd()  { bad=$((bad+1)); printf '  [FAIL] %s\n' "$*"; }
tinte() { python3 -c "
from PIL import Image
from collections import Counter
im=Image.open('$1').convert('RGB'); px=im.load(); W,H=im.size
c=Counter(px[x,y] for y in range(0,H,2) for x in range(0,W,2))
bg,n=c.most_common(1)[0]; tot=sum(c.values())
print(int(100*(tot-n)/tot))" 2>/dev/null || echo 0; }
shot() { printf 'screendump %s\n' "$2.ppm" | socat - "UNIX-CONNECT:$1" >/dev/null 2>&1; sleep 3
    python3 -c "from PIL import Image; Image.open('$2.ppm').save('$2.png')" 2>/dev/null && rm -f "$2.ppm"; }

echo "== 1. install onto an empty disk =="
rm -f "$W/disk.img"; head -c $((256*1024*1024)) /dev/zero > "$W/disk.img"
APPEND="modfs osum vfs gfx wm wig wmhold wmdauer wighalt=3500 nokbd nosched noproc nofs lang=de uiscale=1 wigapp=/bin/installer,now,account=bios,password=geheim123"
timeout 3000 $QEMU_X86 -m 512 -kernel "$BAU/osum.mb" -initrd "$BAU/root.img" -append "$APPEND" \
    -serial "file:$W/inst.txt" -display none -no-reboot \
    -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
    -drive "file=$W/disk.img,format=raw,if=ide,index=0" > "$W/inst.qemu" 2>&1 &
QP=$!
i=0; while [ $i -lt 3000 ]; do
    grep -qa 'installer: fertig\|installer: FEHLER' "$W/inst.txt" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break; sleep 1; i=$((i+1)); done
sleep 3; kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null
grep -qa 'installer: fertig' "$W/inst.txt" && okk "installer finished" || bd "installer did not finish"
grep -qa 'installer: bios stages' "$W/inst.txt" && okk "installer copied limine-bios.sys (stage 3)" \
    || bd "no 'installer: bios stages' (no /boot/limine-hdd.bin in the image?)"

echo "== 2. the host reads the disk with foreign tools =="
sgdisk -v "$W/disk.img" > "$W/sgdisk.txt" 2>&1
grep -q 'No problems found' "$W/sgdisk.txt" && okk "sgdisk -v: no problems (both GPT copies, CRC32s)" \
    || { bd "sgdisk -v complains"; sed 's/^/        /' "$W/sgdisk.txt" | head -8; }
python3 - "$W/disk.img" <<'PY' && okk "MBR: boot code + 0x55AA + protective 0xEE; stage 2 halves in both entry-array tails" || bd "MBR/stage check failed"
import struct, sys, zlib
d = open(sys.argv[1], 'rb')
m = d.read(512)
assert m[510:512] == b'\x55\xaa'
assert sum(1 for b in m[:440] if b) > 100, "no boot code"
assert m[446 + 4] == 0xEE
sa, sb, la, lb = struct.unpack_from('<HHQQ', m, 0x1a4)
assert sa and sb and la and lb, (sa, sb, la, lb)
d.seek(512); h = d.read(92)
assert h[:8] == b'EFI PART'
n, = struct.unpack_from('<I', h, 80); crc, = struct.unpack_from('<I', h, 88)
d.seek(2 * 512); arr = d.read(n * 128)
assert zlib.crc32(arr) == crc, "array crc"
d.seek(la); a = d.read(sa); d.seek(lb); b = d.read(sb)
assert any(a) and any(b)
print('        entries=%d  stage2 A %d B %d bytes at %#x / %#x' % (n, sa, sb, la, lb))
PY
mdir -i "$W/disk.img@@1048576" :: > "$W/esp.txt" 2>&1
grep -qi 'limine-bios\|LIMINE~' "$W/esp.txt" && okk "limine-bios.sys is on the EFI partition" || bd "limine-bios.sys missing on the EFI partition"

boot() { # name  bios|uefi
    local n=$1 how=$2 sock="$W/$1.sock" ser="$W/$1.txt"
    rm -f "$sock" "$ser"; cp -f "$W/disk.img" "$W/$n.img"
    local args=(-machine pc -m 1024 -smp 2 -vga std -display none -no-reboot
                -drive "file=$W/$n.img,format=raw,if=ide,index=0"
                -serial "file:$ser" -monitor "unix:$sock,server,nowait")
    [ -w /dev/kvm ] && args+=(-accel kvm -cpu host)
    if [ "$how" = uefi ]; then
        local code=/usr/share/OVMF/OVMF_CODE.fd; [ -f /usr/share/OVMF/OVMF_CODE_4M.fd ] && code=/usr/share/OVMF/OVMF_CODE_4M.fd
        local vars=/usr/share/OVMF/OVMF_VARS.fd; [ -f /usr/share/OVMF/OVMF_VARS_4M.fd ] && vars=/usr/share/OVMF/OVMF_VARS_4M.fd
        cp -f "$vars" "$W/$n.vars"
        args+=(-drive "if=pflash,format=raw,unit=0,readonly=on,file=$code" -drive "if=pflash,format=raw,unit=1,file=$W/$n.vars")
    fi
    timeout 400 qemu-system-x86_64 "${args[@]}" > "$W/$n.qemu" 2>&1 &
    local q=$! i=0
    while [ $i -lt 300 ]; do grep -qa 'rootpart=' "$ser" 2>/dev/null && break; kill -0 $q 2>/dev/null || break; sleep 1; i=$((i+1)); done
    sleep 25; shot "$sock" "$W/$n"
    printf 'quit\n' | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1; wait $q 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$ser" > "$ser.klar"
    grep -qa 'rootpart=1' "$ser" && okk "$n: the kernel found its root on the disk (rootpart=1)" || bd "$n: no rootpart=1"
    grep -qa 'from module' "$ser" && bd "$n: root came from a module -- the stick was involved" || okk "$n: no stick involved"
    t=$(tinte "$W/$n.png" 2>/dev/null); [ "${t:-0}" -ge 2 ] && okk "$n: picture with the sign-in screen (${t} % ink)" || bd "$n: screen empty (${t:-0} % ink)"
    rm -f "$W/$n.img"
}
echo "== 3a. SeaBIOS (Legacy BIOS) =="; boot seabios bios
echo "== 3b. OVMF (UEFI) =="; boot ovmf uefi
rm -f "$W/disk.img" "$W"/*.vars
echo "BIOS-BOOT: $ok ok, $bad failed"
[ "$bad" = 0 ]
