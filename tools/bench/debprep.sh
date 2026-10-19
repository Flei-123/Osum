#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bench/debprep.sh <debian-nocloud.qcow2> <out.qcow2> -- r1212: make the Debian nocloud image boot straight to a login prompt.
# The first boot starts systemd-firstboot (a wizard that reads /dev/console = the VGA console, never the serial line) and leaves root
# locked ("!unprovisioned"). We patch the root file system offline with debugfs (no loop device / nbd needed): a fixed machine-id
# (= not a first boot) and an empty root password. Work files live in a private mktemp dir.
set -euo pipefail
IN=${1:?usage: debprep.sh <in.qcow2> <out.qcow2>}; OUT=${2:?usage: debprep.sh <in.qcow2> <out.qcow2>}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
qemu-img convert -O raw "$IN" "$T/d.raw"
read -r START SIZE < <(sfdisk -d "$T/d.raw" | awk '/type=4F68BCE3/ {gsub(",","",$4); gsub(",","",$6); print $4, $6}')
[ -n "${START:-}" ] || { echo "debprep: root partition not found" >&2; exit 1; }
dd if="$T/d.raw" of="$T/root.ext4" bs=512 skip="$START" count="$SIZE" status=none
debugfs -R "cat /etc/shadow" "$T/root.ext4" 2>/dev/null | sed 's/^root:[^:]*:/root::/' > "$T/shadow"
grep -q '^root::' "$T/shadow" || { echo "debprep: no root line in /etc/shadow" >&2; exit 1; }
echo 0123456789abcdef0123456789abcdef > "$T/mid"
debugfs -w -f - "$T/root.ext4" >/dev/null 2>&1 <<EOF
rm /etc/shadow
write $T/shadow /etc/shadow
set_inode_field /etc/shadow mode 0100640
set_inode_field /etc/shadow uid 0
set_inode_field /etc/shadow gid 42
rm /etc/machine-id
write $T/mid /etc/machine-id
set_inode_field /etc/machine-id mode 0100444
EOF
[ "$(debugfs -R 'cat /etc/machine-id' "$T/root.ext4" 2>/dev/null)" = "0123456789abcdef0123456789abcdef" ] || { echo "debprep: patch failed" >&2; exit 1; }
dd if="$T/root.ext4" of="$T/d.raw" bs=512 seek="$START" conv=notrunc status=none
qemu-img convert -c -O qcow2 "$T/d.raw" "$OUT"
