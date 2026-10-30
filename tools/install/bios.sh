#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/install/bios.sh -- r2323: the installer writes the osboot BIOS stage
# (stage0 in the MBR, stage2 at LBA 256) and the installed disk boots through
# SeaBIOS and through OVMF without the stick.
#
#   bash tools/install/bios.sh <image-dir> [work-dir]
#
# <image-dir> is the output of OSBOOT=1 tools/usbimg/build.sh (osum.mb, root.img,
# osboot-bios/osboot-stage{0,2}.bin).
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
BAU=${1:?image dir}; W=${2:-$(mktemp -d /root/abbilder/instbios.XXXXXX)}
[ -n "${KEEP:-}" ] || trap 'rm -rf "$W"' EXIT
mkdir -p "$W"
ok=0; bad=0
okk() { ok=$((ok+1)); printf '  [ ok ] %s\n' "$*"; }
bd()  { bad=$((bad+1)); printf '  [FAIL] %s\n' "$*"; }

if [ -n "${DISK_IMG:-}" ]; then
    echo "== 1. reusing the installed disk $DISK_IMG =="
    cp "$DISK_IMG" "$W/disk.img"
    okk "installed disk reused"
else
    echo "== 1. install onto an empty disk =="
    head -c $((256*1024*1024)) /dev/zero > "$W/disk.img"
    APPEND="modfs osum vfs gfx wm wig wmhold wmdauer wighalt=3500 nokbd nosched noproc nofs lang=de uiscale=1 wigapp=/bin/installer,now,account=bios,password=geheim123"
    timeout 3000 $QEMU_X86 -m 512 -kernel "$BAU/osum.mb" -initrd "$BAU/root.img" -append "$APPEND" \
        -serial "file:$W/inst.txt" -display none -no-reboot \
        -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
        -drive "file=$W/disk.img,format=raw,if=ide,index=0" > "$W/inst.qemu" 2>&1 &
    QP=$!
    i=0; while [ $i -lt 3000 ]; do
        grep -qa 'installer: done\|installer: ERROR' "$W/inst.txt" 2>/dev/null && break
        kill -0 "$QP" 2>/dev/null || break; sleep 1; i=$((i+1)); done
    sleep 3; kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null
    grep -qa 'installer: done' "$W/inst.txt" && okk "installer finished" || bd "installer did not finish"
    grep -qa 'installer: osboot bios stage' "$W/inst.txt" && okk "installer reports the osboot bios stage" \
        || bd "no 'installer: osboot bios stage' line"
fi
mcopy -i "$W/disk.img@@1048576" ::limine.conf "$W/limine.conf" 2>/dev/null
sed -i 's/ nosched noproc nofs//' "$W/limine.conf"
mcopy -o -i "$W/disk.img@@1048576" "$W/limine.conf" ::limine.conf 2>/dev/null \
    && okk "installer-run test words removed from the installed command line" || bd "could not patch limine.conf"

echo "== 2. the host reads the disk with foreign tools =="
sgdisk -v "$W/disk.img" > "$W/sgdisk.txt" 2>&1
grep -q 'No problems found' "$W/sgdisk.txt" && okk "sgdisk -v: no problems (both GPT copies, CRC32s)" \
    || { bd "sgdisk -v complains"; sed 's/^/        /' "$W/sgdisk.txt" | head -8; }
python3 -I - "$W/disk.img" "$BAU/osboot-bios/osboot-stage0.bin" "$BAU/osboot-bios/osboot-stage2.bin" <<'PY' \
    && okk "MBR: stage0 bytes + parameters (esp, stage2 lba/sectors, magic) + 0xEE + 0x55AA; stage2 identical at LBA 256" \
    || bd "MBR/stage check failed"
import struct, sys
disk, s0, s2 = sys.argv[1:4]
stage0 = open(s0, "rb").read()
stage2 = open(s2, "rb").read()
d = open(disk, "rb")
m = d.read(512)
assert m[510:512] == b"\x55\xaa", "no 55AA"
assert m[:424] == stage0[:424], "stage0 code differs"
esp, lba, sectors, magic = struct.unpack_from("<IIII", m, 424)
assert magic == 0x3042534F, hex(magic)
assert lba == 256, lba
assert sectors == (len(stage2) + 511) // 512, (sectors, len(stage2))
assert m[446 + 4] == 0xEE, "no protective entry"
d.seek(512)
h = d.read(92)
assert h[:8] == b"EFI PART"
d.seek(lba * 512)
got = d.read(sectors * 512)
assert got[:len(stage2)] == stage2, "stage2 differs"
assert not any(got[len(stage2):]), "stage2 padding not zero"
d.seek(2 * 512)
assert esp * 512 > lba * 512 + len(got)
print("        esp lba %d, stage2 lba %d, %d sectors" % (esp, lba, sectors))
PY
mdir -i "$W/disk.img@@1048576" :: > "$W/esp.txt" 2>&1
grep -qi 'osboot' "$W/esp.txt" && okk "osboot.cfg is on the EFI partition" || bd "osboot.cfg missing on the EFI partition"
grep -qi 'limine-bios' "$W/esp.txt" && bd "limine-bios.sys copied although the osboot stage is used" \
    || okk "no limine-bios.sys on the EFI partition"

boot() {
    local n=$1 how=$2 img=$3 sock="$W/$1.sock" ser="$W/$1.txt"
    rm -f "$sock" "$ser"; cp -f "$img" "$W/$n.img"
    local args=(-machine pc -m 1024 -smp 2 -vga std -display none -no-reboot
                -serial "file:$ser" -monitor "unix:$sock,server,nowait")
    if [ "${BUS:-ahci}" = ahci ]; then
        args+=(-device ich9-ahci,id=ahci0 -drive "if=none,id=hd0,file=$W/$n.img,format=raw" -device ide-hd,drive=hd0,bus=ahci0.0)
    else
        args+=(-drive "file=$W/$n.img,format=raw,if=ide,index=0")
    fi
    [ -w /dev/kvm ] && args+=(-accel kvm -cpu host)
    if [ "$how" = uefi ]; then
        local code=/usr/share/OVMF/OVMF_CODE.fd; [ -f /usr/share/OVMF/OVMF_CODE_4M.fd ] && code=/usr/share/OVMF/OVMF_CODE_4M.fd
        local vars=/usr/share/OVMF/OVMF_VARS.fd; [ -f /usr/share/OVMF/OVMF_VARS_4M.fd ] && vars=/usr/share/OVMF/OVMF_VARS_4M.fd
        cp -f "$vars" "$W/$n.vars"
        args+=(-drive "if=pflash,format=raw,unit=0,readonly=on,file=$code" -drive "if=pflash,format=raw,unit=1,file=$W/$n.vars")
    fi
    timeout 400 qemu-system-x86_64 "${args[@]}" > "$W/$n.qemu" 2>&1 &
    local q=$! i=0 want=${4:-glogin: bereit} secs=${5:-300}
    while [ $i -lt "$secs" ]; do
        grep -qa "$want\|EXCEPTION" "$ser" 2>/dev/null && break
        kill -0 $q 2>/dev/null || break; sleep 1; i=$((i+1)); done
    sleep "${6:-2}"
    printf 'quit\n' | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1; kill $q 2>/dev/null; wait $q 2>/dev/null
    rm -f "$W/$n.img"
}

check_login() {
    local n=$1 banner=$2 ser="$W/$1.txt"
    [ -n "$banner" ] && { grep -aq "$banner" "$ser" && okk "$n: $banner" || bd "$n: no '$banner' line"; }
    grep -aq "osboot: start " "$ser" && okk "$n: osboot started the kernel" || bd "$n: no 'osboot: start' line"
    grep -aqE "rootpart=1|rootsel: [a-z]+ -- WURZEL, Bloecke=[0-9]+ +first=72048" "$ser" && okk "$n: the kernel found its root on the disk" || bd "$n: no root found on the disk"
    grep -aq "from module" "$ser" && bd "$n: root came from a module -- the stick was involved" || okk "$n: no stick involved"
    grep -aq "glogin: bereit" "$ser" && okk "$n: login screen reached" || bd "$n: login screen not reached"
    grep -aq "EXCEPTION\|kernel halted\|panic:" "$ser" && bd "$n: fault: $(grep -a 'EXCEPTION\|kernel halted\|panic:' "$ser" | head -1)" || okk "$n: no fault line"
}

echo "== 3a. SeaBIOS (Legacy BIOS), AHCI disk =="
boot seabios bios "$W/disk.img"
check_login seabios "osboot (bios)"

echo "== 3a2. SeaBIOS, IDE disk: the stage loads and starts the kernel =="
BUS=ide boot seabioside bios "$W/disk.img" "rootpart=" 120 1
grep -aq "osboot (bios)" "$W/seabioside.txt" && okk "seabioside: osboot (bios)" || bd "seabioside: no loader banner"
grep -aq "osboot: start " "$W/seabioside.txt" && okk "seabioside: osboot started the kernel" || bd "seabioside: no 'osboot: start' line"
grep -aqE "rootpart=1|rootsel: [a-z]+ -- WURZEL" "$W/seabioside.txt" && okk "seabioside: root found on the disk" || bd "seabioside: no root found on the disk"

echo "== 3b. OVMF (UEFI) =="
boot ovmf uefi "$W/disk.img"
check_login ovmf ""

echo "== 3c. counter-proof: stage2 zeroed on a copy of the installed disk =="
cp "$W/disk.img" "$W/nostage.img"
python3 -I - "$W/nostage.img" <<'PY'
import sys
with open(sys.argv[1], "r+b") as f:
    f.seek(256 * 512)
    f.write(bytes(512 * 200))
PY
boot nostg bios "$W/nostage.img" "osboot (bios)" 25 0
grep -aq "osboot (bios)" "$W/nostg.txt" && bd "nostage: loader banner despite zeroed stage2" || okk "nostage: no loader banner without the stage"
grep -aq "rootpart=\|glogin: bereit" "$W/nostg.txt" && bd "nostage: the kernel started anyway" || okk "nostage: the kernel did not start"

echo "== 3d. counter-proof: MBR stage0 zeroed on a copy of the installed disk =="
cp "$W/disk.img" "$W/nombr.img"
python3 -I - "$W/nombr.img" <<'PY'
import sys
with open(sys.argv[1], "r+b") as f:
    f.write(bytes(440))
PY
boot nomb bios "$W/nombr.img" "osboot (bios)" 25 0
grep -aq "osboot (bios)" "$W/nomb.txt" && bd "nombr: loader banner despite zeroed stage0" || okk "nombr: no loader banner without stage0"

rm -f "$W/disk.img" "$W/nostage.img" "$W/nombr.img" "$W"/*.vars
echo "BIOS-INSTALL: $ok ok, $bad failed"
[ "$bad" = 0 ]
