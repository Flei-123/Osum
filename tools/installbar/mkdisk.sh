#!/usr/bin/env bash
set -uo pipefail
OUT=${1:?output dir}
ESP_START=2048
ESP_SECT=69632
NTFS_START=$((ESP_START + ESP_SECT))
NTFS_SECT=409600
DISK_SECT=$((NTFS_START + NTFS_SECT + 2048))
cd "$(dirname "$0")/../.."
python3 -I tools/ntfsshrink/endmake.py "$OUT" inst4k "$NTFS_SECT" >/dev/null || exit 1
python3 -I - "$OUT/disk.img" "$DISK_SECT" <<'PY'
import sys
f = open(sys.argv[1], 'wb'); f.seek(int(sys.argv[2]) * 512 - 1); f.write(b'\0'); f.close()
PY
sgdisk -o "$OUT/disk.img" >/dev/null 2>&1
sgdisk -n "1:$ESP_START:$((ESP_START + ESP_SECT - 1))" -t 1:EF00 -c 1:"EFI System Partition" "$OUT/disk.img" >/dev/null 2>&1
sgdisk -n "2:$NTFS_START:$((NTFS_START + NTFS_SECT - 1))" -t 2:0700 -c 2:"Basic data partition" "$OUT/disk.img" >/dev/null 2>&1
dd if=/dev/zero of="$OUT/esp.part" bs=512 count="$ESP_SECT" status=none
mkfs.vfat -F 32 -n SYSTEM "$OUT/esp.part" >/dev/null 2>&1
dd if="$OUT/esp.part" of="$OUT/disk.img" bs=512 seek="$ESP_START" conv=notrunc status=none
dd if="$OUT/inst4k.part" of="$OUT/disk.img" bs=512 seek="$NTFS_START" conv=notrunc status=none
rm -f "$OUT/esp.part" "$OUT/inst4k.part"
sgdisk -v "$OUT/disk.img" | grep -q 'No problems found'
