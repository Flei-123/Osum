#!/usr/bin/env bash
set -uo pipefail
OUT=${1:?output dir}
GAP_MIB=${2:-0}
OSUM_MIB=${3:-0}
OSUM_SECT=$((OSUM_MIB * 2048))
ESP_START=2048
ESP_SECT=409600
MSR_START=$((ESP_START + ESP_SECT))
MSR_SECT=32768
NTFS_START=$((MSR_START + MSR_SECT))
NTFS_SECT=409600
OSUM_START=$((NTFS_START + NTFS_SECT))
REC_START=$((OSUM_START + OSUM_SECT))
REC_SECT=40960
DISK_SECT=$((REC_START + REC_SECT + 2048 + GAP_MIB * 2048))
cd "$(dirname "$0")/../.."
python3 -I tools/ntfsshrink/endmake.py "$OUT" inst4k "$NTFS_SECT" >/dev/null || exit 1
python3 -I - "$OUT/disk.img" "$DISK_SECT" "$OUT/inst4k.part" <<'PY'
import sys
f = open(sys.argv[1], 'wb'); f.seek(int(sys.argv[2]) * 512 - 1); f.write(b'\0'); f.close()
g = open(sys.argv[3], 'r+b'); g.seek(3); g.write(b'-FVE-FS-'); g.close()
PY
sgdisk -o "$OUT/disk.img" >/dev/null 2>&1
sgdisk -n "1:$ESP_START:$((ESP_START + ESP_SECT - 1))" -t 1:EF00 -c 1:"Basic data partition" "$OUT/disk.img" >/dev/null 2>&1
sgdisk -n "2:$MSR_START:$((MSR_START + MSR_SECT - 1))" -t 2:0C01 -c 2:"Microsoft reserved partition" "$OUT/disk.img" >/dev/null 2>&1
sgdisk -n "3:$NTFS_START:$((NTFS_START + NTFS_SECT - 1))" -t 3:0700 -c 3:"Basic data partition" "$OUT/disk.img" >/dev/null 2>&1
sgdisk -n "4:$REC_START:$((REC_START + REC_SECT - 1))" -t 4:2700 -c 4:"Basic data partition" "$OUT/disk.img" >/dev/null 2>&1
dd if=/dev/zero of="$OUT/esp.part" bs=512 count="$ESP_SECT" status=none
mkfs.vfat -F 32 -n SYSTEM "$OUT/esp.part" >/dev/null 2>&1
if [ "$OSUM_MIB" -gt 0 ]; then
    sgdisk -n "5:$OSUM_START:$((OSUM_START + OSUM_SECT - 1))" -t 5:4F53554D-4F46-5301-8E75-6D6F72694F53 -c 5:OSUM "$OUT/disk.img" >/dev/null 2>&1
    head -c $((OSUM_MIB * 1048576)) /dev/urandom > "$OUT/osum.part"
    dd if="$OUT/osum.part" of="$OUT/disk.img" bs=512 seek="$OSUM_START" conv=notrunc status=none
    rm -f "$OUT/osum.part"
fi
dd if="$OUT/esp.part" of="$OUT/disk.img" bs=512 seek="$ESP_START" conv=notrunc status=none
dd if="$OUT/inst4k.part" of="$OUT/disk.img" bs=512 seek="$NTFS_START" conv=notrunc status=none
rm -f "$OUT/esp.part" "$OUT/inst4k.part"
sgdisk -v "$OUT/disk.img" | grep -q 'No problems found'
