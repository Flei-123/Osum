#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/nodmg/run.sh -- a stick boot must not change any foreign disk.
# Three foreign disks (IDE hdb, NVMe, AHCI) carry a random pattern + GPT signature.
# Case 1 (lock): raw writes + installer/dual calls without confirmation -> sha256 unchanged.
# Case 2 (nowlock, counter-proof): same raw writes with the kernel word nowlock -> sha256 MUST change.
# Case 3 (confirmed): install /dev/hdb --ja --name hdb -> allowed, hdb changes, nvme/ahci untouched.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
W=$(mktemp -d)
trap '[ -n "${NODMG_KEEP:-}" ] || rm -rf "$W"' EXIT
OUT=${1:-}
if [ -z "$OUT" ]; then
    OUT="$W/inst"
    bash tools/install/build.sh "$OUT" > "$W/build.log" 2>&1 || { echo "FAIL build: $(tail -n 3 "$W/build.log" | tr '\n' ' ')"; echo "nodmg gate: 0/1 OK/FAIL"; exit 1; }
fi
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "OK   $*"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL $*"; }
for d in hdb nvme sda; do
    python3 - "$W/$d.img" "$d" <<'P'
import sys, random
r = random.Random(sys.argv[2])
b = bytearray(r.randbytes(2 * 1024 * 1024))
b[510:512] = b"\x55\xaa"
b[512:520] = b"EFI PART"
f = open(sys.argv[1], "wb")
f.write(b)
f.seek(256 * 1024 * 1024 - 1)
f.write(b"\0")
f.close()
P
done
CRC=$(cat "$OUT/quelle.crc")
sums() { sha256sum "$W/hdb.img" "$W/nvme.img" "$W/sda.img" | cut -d' ' -f1 | tr '\n' ' '; }
run() {
    local name=$1 extra=$2 script=$3
    cp "$OUT/ziel.img" "$W/ziel.img"
    : > "$W/$name.txt"
    timeout ${T:-150} $QEMU_X86 -machine pc -cpu max -m 512 -smp 1 \
        -kernel "$OUT/k.mb" -initrd "$OUT/quelle.img" \
        -append "osum vfs nokbd nosched noproc nofs noring3 modfs modcrc=$CRC $extra ${script:+script=$script}" \
        -serial "file:$W/$name.txt" -display none -no-reboot \
        -drive "file=$W/ziel.img,format=raw,if=none,id=zi" -device ide-hd,drive=zi,bus=ide.0 \
        -drive "file=$W/hdb.img,format=raw,if=none,id=hb" -device ide-hd,drive=hb,bus=ide.0,unit=1 \
        -drive "file=$W/nvme.img,format=raw,if=none,id=nv" -device nvme,drive=nv,serial=nodmg1 \
        -device ahci,id=ahci -drive "file=$W/sda.img,format=raw,if=none,id=sd" -device ide-hd,drive=sd,bus=ahci.0 \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
}
S0=$(sums)
run lockide "" "cp /bin/sh /dev/hdb;install /dev/hdb --ja;install /dev/ram0 --ja;install /dev/usb --ja;exit"
T=45 run lockn "nvme wlforeign" ""
T=45 run locka "ahci wlforeign" ""
S1=$(sums)
[ "$S0" = "$S1" ] && ok "lock: IDE, NVMe and AHCI foreign disks bit-identical" || bad "lock: a foreign disk changed"
grep -a -q "cannot write /dev/hdb" "$W/lockide.txt" && ok "lock: raw write to hdb refused" || bad "lock: hdb write not refused"
grep -a -q "wlock: write denied dev=2" "$W/lockn.txt" && grep -a -q "nvme: wrote=0" "$W/lockn.txt" && ok "lock: nvme write hook denied" || bad "lock: nvme hook"
grep -a -q "wlock: write denied dev=5" "$W/locka.txt" && grep -a -q "ahci: wrote=0" "$W/locka.txt" && ok "lock: ahci write hook denied" || bad "lock: ahci hook"
grep -a -q "wipe: partitions exist" "$W/lockide.txt" && ok "lock: installer asks for typed name" || bad "lock: installer did not ask for name"
grep -a -q "wipe: refused" "$W/lockide.txt" && ok "lock: ram0/usb refused" || bad "lock: ram0/usb not refused"
run nolockide "nowlock" "cp /bin/sh /dev/hdb;exit"
T=45 run nolockn "nvme wlforeign nowlock" ""
T=45 run nolocka "ahci wlforeign nowlock" ""
[ "$(sha256sum "$W/hdb.img" | cut -c1-64)" != "$(echo "$S1" | cut -d' ' -f1)" ] && ok "COUNTER-PROOF nowlock: hdb changes" || bad "COUNTER-PROOF: hdb unchanged (gate blind)"
[ "$(sha256sum "$W/nvme.img" | cut -c1-64)" != "$(echo "$S1" | cut -d' ' -f2)" ] && ok "COUNTER-PROOF nowlock: nvme changes" || bad "COUNTER-PROOF: nvme unchanged"
[ "$(sha256sum "$W/sda.img" | cut -c1-64)" != "$(echo "$S1" | cut -d' ' -f3)" ] && ok "COUNTER-PROOF nowlock: ahci changes" || bad "COUNTER-PROOF: ahci unchanged"
S3a=$(sums)
T=75 run conf "" "install /dev/hda --ja;exit"
S3b=$(sums)
grep -a -q "wipe: unlocked" "$W/conf.txt" && ok "confirmed: unlock granted" || bad "confirmed: no unlock"
grep -a -q "install: fat32 ok" "$W/conf.txt" && ok "confirmed: install wrote GPT + FAT32 on blank hda (full run: tools/install/run.sh)" || bad "confirmed: install did not write"
[ "$S3a" = "$S3b" ] && ok "confirmed: foreign disks untouched" || bad "confirmed: foreign disk changed"
echo "nodmg gate: $PASS/$FAIL OK/FAIL"
[ "$FAIL" = 0 ]
