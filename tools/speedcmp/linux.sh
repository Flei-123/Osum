#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/speedcmp/common.sh
OUT=${1:?outdir}; BENCH=${2:?bench binary}; IMG=${3:?debian qcow2}
LINUX_DRIVE=${LINUX_DRIVE:-ahci}
mkdir -p "$OUT"
LIBC=$(resolve_musl_libc) || { echo "linux: no musl libc.so" >&2; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

qemu-img convert -O raw "$IMG" "$W/d.raw" || exit 1
read -r START SIZE < <(sfdisk -d "$W/d.raw" | awk '/type=4F68BCE3/ {gsub(",","",$4); gsub(",","",$6); print $4, $6}')
[ -n "${START:-}" ] || { echo "linux: root partition not found" >&2; exit 1; }
dd if="$W/d.raw" of="$W/root.ext4" bs=512 skip="$START" count="$SIZE" status=none
rm -f "$W/d.raw"

cat > "$W/speedinit" <<'INIT'
#!/bin/sh
mount -t proc proc /proc
[ -e /dev/zero ] || mount -t devtmpfs dev /dev
echo 1 > /proc/sys/kernel/sysrq
/usr/bin/speedbench
echo o > /proc/sysrq-trigger
INIT
KERNEL_FILE=$(debugfs -R "ls -p /boot" "$W/root.ext4" 2>/dev/null | awk -F/ '$6 ~ /^vmlinuz-/ {print $6; exit}')
INITRD_FILE=$(debugfs -R "ls -p /boot" "$W/root.ext4" 2>/dev/null | awk -F/ '$6 ~ /^initrd.img-/ {print $6; exit}')
[ -n "$KERNEL_FILE" ] && [ -n "$INITRD_FILE" ] || { echo "linux: kernel/initrd not found in /boot" >&2; exit 1; }
debugfs -R "dump /boot/$KERNEL_FILE $W/vmlinuz" "$W/root.ext4" >/dev/null 2>&1
debugfs -R "dump /boot/$INITRD_FILE $W/initrd" "$W/root.ext4" >/dev/null 2>&1
debugfs -w -f - "$W/root.ext4" >/dev/null 2>&1 <<DEBUGFS
rm /usr/bin/speedbench
write $BENCH /usr/bin/speedbench
set_inode_field /usr/bin/speedbench mode 0100755
rm /usr/lib/ld-musl-x86_64.so.1
write $LIBC /usr/lib/ld-musl-x86_64.so.1
set_inode_field /usr/lib/ld-musl-x86_64.so.1 mode 0100755
rm /usr/bin/speedinit
write $W/speedinit /usr/bin/speedinit
set_inode_field /usr/bin/speedinit mode 0100755
DEBUGFS
[ -s "$W/vmlinuz" ] && [ -s "$W/initrd" ] || { echo "linux: kernel/initrd dump failed" >&2; exit 1; }
echo "linux kernel: $KERNEL_FILE" > "$OUT/linux-kernel.txt"

drive_args "$LINUX_DRIVE" "$W/root.ext4" ,snapshot=on || exit 1
for i in $(seq 1 "$SPEED_RUNS"); do
    timeout "$SPEED_BOOT_TIMEOUT" qemu-system-x86_64 "${SPEED_KVM[@]}" -smp "$SPEED_SMP" -m "$SPEED_MEM" -kernel "$W/vmlinuz" -initrd "$W/initrd" \
        -append "root=$DRIVE_ROOT rw rootfstype=ext4 console=ttyS0 quiet panic=1 init=/usr/bin/speedinit" \
        "${DRIVE_ARGS[@]}" -display none -no-reboot -nographic -serial "file:$OUT/linux-$i.raw" -monitor none -net none > /dev/null 2>&1
    echo "linux run $i rc=$?" >&2
    grep -a '^S ' "$OUT/linux-$i.raw" | tr -d '\r' > "$OUT/linux-$i.txt"
done
