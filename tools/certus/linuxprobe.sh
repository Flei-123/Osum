#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/certus/linuxprobe.sh -- does the UNMODIFIED Linux build of Certus start on OrientOS?
#
#   /root/jarvis/bin/heavy bash tools/certus/linuxprobe.sh [certus-linux-binary]
#
# Boots the current kernel with a minimal disk (sh ls cat echo + the Linux
# Certus binary as /bin/certus-lin), runs it with KARGS=fremdtrace and prints
# what the ELF loader / kernel said. It measures, it does not fix anything.
# Output lines: "PROBE <key> <value>". Exit 0 always (it is a measurement).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
BIN=${1:-/root/rel71/certus-071-linux}
TMO=${TMO:-200}
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
export FIRNLIB="$ROOT/lib"
QEMU=${QEMU_X86:-qemu-system-x86_64}
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
[ -r "$BIN" ] || { echo "PROBE binary missing $BIN"; exit 0; }

bash vendor/firn/fetch-firnc.sh > "$D/firnc.log" 2>&1
bash tools/build-kernel.sh "$D/k.mb" --stufe 1 > "$D/kernel.log" 2>&1 || { echo "PROBE kernel-build FAIL"; tail -5 "$D/kernel.log"; exit 0; }

mkdir -p "$D/p"
as --64 -o "$D/crt.o" kernel/user/crt.s
spec="/bin/ /tmp/ /etc/ /dev/ /proc/ /sys/ /root/ /lib/"
for p in sh ls cat echo; do
    vendor/firn/bin/firnc1 "kernel/user/$p.fi" -o "$D/p/$p.o" > "$D/p/$p.log" 2>&1 || { echo "PROBE prog-build FAIL $p"; exit 0; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F1.u_start" -o "$D/p/$p.elf" "$D/crt.o" "$D/p/$p.o" 2>>"$D/p/$p.log" || exit 0
    strip --strip-all "$D/p/$p.elf" 2>/dev/null
    spec="$spec /bin/$p=$D/p/$p.elf"
done
cp "$BIN" "$D/certus-lin"; strip --strip-all "$D/certus-lin" 2>/dev/null
echo "PROBE binary-bytes $(stat -c%s "$D/certus-lin")"
echo "PROBE binary-load-segments $(readelf -lW "$D/certus-lin" | awk '/LOAD/{printf "%s(%s) ", $3, $6}')"
printf 'nameserver 10.0.2.3\n' > "$D/resolv.conf"
spec="$spec /bin/certus-lin=$D/certus-lin /etc/resolv.conf=$D/resolv.conf"
python3 tools/osum/mkfs.py build "$D/disk.img" 98304 --v3 --inodes=1024 $spec > "$D/mkfs.txt" 2>&1 \
    || { echo "PROBE mkfs FAIL"; tail -3 "$D/mkfs.txt"; exit 0; }

timeout "$TMO" $QEMU "${KVM[@]}" -smp 1 -kernel "$D/k.mb" -m 512 \
    -append "osum vfs nokbd nosched noproc nofs fremdtrace script=/bin/certus-lin;exit" \
    -serial "file:$D/ser.txt" -display none -no-reboot \
    -drive "file=$D/disk.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
echo "PROBE qemu-rc $?"
grep -a -iE "elf|exec|reject|abgelehnt|nosys|enosys|certus" "$D/ser.txt" | head -20 | sed 's/^/PROBE serial: /'
echo "PROBE serial-lines $(wc -l < "$D/ser.txt")"
