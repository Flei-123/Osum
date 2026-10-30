#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/crashflush/run.sh -- r2358b gate: a kernel panic report on an NVMe root is flushed to the device (FLUSH command) before the
# RAM copy is dropped; the report on disk holds its text, not zeros.
#
#   /root/jarvis/bin/heavy bash tools/crashflush/run.sh
#
# A  NVMe root, forced kernel panic: serial 'crash: report flushed, device +1', QEMU trace sees pci_nvme_flush_ns, /var/crash/<n>.txt
#    on the image starts with the report header.
# B  counter-proof `nocacheflush`: device +0 and QEMU sees exactly one NVMe flush command less than in A.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
ACCEL=""
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then ACCEL="-accel kvm -cpu host"; fi
K0=${CRASHFLUSH_KERNEL:-}
if [ -z "$K0" ]; then
    bash tools/build-kernel.sh "$TMPD/k0.mb" > "$TMPD/build.log" 2>&1 || { bad "kernel build"; tail -5 "$TMPD/build.log"; exit 1; }
    K0="$TMPD/k0.mb"
fi
as --64 -o "$TMPD/crt.o" kernel/user/crt.s || bad "crt.s"
PROGS="sh ls cat echo krach"
quelle() { case $1 in krach) echo noise ;; *) echo "$1" ;; esac; }
for p in $PROGS; do
    q=$(quelle "$p")
    "$FIRNC" "kernel/user/$q.fi" -o "$TMPD/$p.o" > "$TMPD/e$p" 2>&1 || { bad "$q.fi compile"; head -5 "$TMPD/e$p"; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || bad "$p link"
done
SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
CL="osum nokbd vfs krach script=krach kern;exit"

boot() { # <tag> <extra words>
    local t=$1 img="$TMPD/$1.img"
    python3 tools/osum/mkfs.py build "$img" 4096 $SPEC /proc/ /dev/ /mnt/ /var/ /var/crash/ > "$TMPD/mkfs-$t.txt" 2>&1 || bad "$t mkfs"
    timeout 90 qemu-system-x86_64 $ACCEL -kernel "$K0" -m 256 -append "$CL $2" -serial "file:$TMPD/$t.ser" -display none -no-reboot \
        -drive "file=$img,format=raw,if=none,id=nv" -device nvme,drive=nv,serial=cflush \
        -trace "pci_nvme_flush_ns,file=$TMPD/$t.trace" -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    touch "$TMPD/$t.trace"
}

echo "== A. panic on NVMe root: report flushed =="
boot a ""
grep -aq 'rootsel: .*nvme' "$TMPD/a.ser" && ok "A root picked on nvme" || bad "A rootsel nvme line missing"
grep -aq 'absturz: bericht .* geschrieben' "$TMPD/a.ser" && ok "A report written" || bad "A report written line missing"
grep -aq 'crash: report flushed, device +1' "$TMPD/a.ser" && ok "A report flushed, device +1" || bad "A flush line: $(grep -a 'report flushed' "$TMPD/a.ser" | head -1)"
na=$(grep -c pci_nvme_flush_ns "$TMPD/a.trace")
[ "$na" -gt 0 ] && ok "A qemu saw NVMe flush commands: $na" || bad "A qemu saw no NVMe flush"
f=$(python3 tools/osum/mkfs.py list "$TMPD/a.img" 2>/dev/null | grep -oE "var/crash/[0-9]+\.txt" | head -1 | sed "s,.*/,,")
if [ -n "$f" ]; then
    python3 tools/osum/mkfs.py cat "$TMPD/a.img" "/var/crash/$f" > "$TMPD/a.rep" 2>/dev/null
    nz=$(tr -d '\0' < "$TMPD/a.rep" | wc -c)
    [ "$nz" -gt 200 ] && ok "A report on disk has $nz non-zero octets" || bad "A report on disk empty ($nz)"
    grep -aq 'OSUM' "$TMPD/a.rep" && ok "A report header on disk" || bad "A report header missing on disk"
else
    bad "A no /var/crash/<n>.txt on the image"
fi

echo "== B. counter-proof nocacheflush =="
boot b "nocacheflush"
grep -aq 'crash: report flushed, device +0' "$TMPD/b.ser" && ok "B nocacheflush: device +0" || bad "B flush line: $(grep -a 'report flushed' "$TMPD/b.ser" | head -1)"
nb=$(grep -c pci_nvme_flush_ns "$TMPD/b.trace")
[ "$((na - nb))" -eq 1 ] && ok "B qemu saw exactly the report flush less: $na -> $nb" || bad "B qemu flushes $na -> $nb (want one less)"
if [ -n "${CRASHFLUSH_OUT:-}" ]; then mkdir -p "$CRASHFLUSH_OUT"; cp "$TMPD"/*.ser "$TMPD"/*.trace "$TMPD"/a.rep "$CRASHFLUSH_OUT/" 2>/dev/null; fi
echo "crashflush: $pass/$fail OK/FAIL"
[ "$fail" -eq 0 ]
