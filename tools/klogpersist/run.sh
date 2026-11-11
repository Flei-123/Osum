#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
. tools/lib/firnenv.sh
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
ACCEL=""
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then ACCEL="-accel kvm -cpu host"; fi
K0=${KLOGPERSIST_KERNEL:-}
if [ -z "$K0" ]; then
    bash tools/build-kernel.sh "$TMPD/k0.mb" > "$TMPD/build.log" 2>&1 || { bad "kernel build"; tail -5 "$TMPD/build.log"; exit 1; }
    K0="$TMPD/k0.mb"
fi
as --64 -o "$TMPD/crt.o" kernel/user/crt.s || bad "crt.s"
PROGS="sh ls cat echo wc krach dmesg klog"
for p in $PROGS; do
    q=$p; [ "$p" = krach ] && q=noise
    "$FIRNC" "kernel/user/$q.fi" -o "$TMPD/$p.o" > "$TMPD/e$p" 2>&1 || { bad "$q.fi compile"; head -5 "$TMPD/e$p"; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || bad "$p link"
done
SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
IMG="$TMPD/disk.img"
bash tools/mkfsfi/mkfs.sh build "$IMG" 4096 $SPEC /proc/ /dev/ /mnt/ /var/ /var/crash/ > "$TMPD/mkfs.txt" 2>&1 || bad "mkfs"

boot() {
    local t=$1 script=$2
    timeout 120 qemu-system-x86_64 $ACCEL -kernel "$K0" -m 256 -append "osum nokbd vfs krach script=$script" -serial "file:$TMPD/$t.ser" \
        -display none -no-reboot -drive "file=$IMG,format=raw,if=none,id=nv" -device nvme,drive=nv,serial=klogp \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
}

echo "== 1. clean boot: save, next boot reads the previous one =="
boot b1 "klog -a GATEMARK_ONE;klog -x;exit"
grep -aq 'saved lines: [1-9]' "$TMPD/b1.ser" && ok "b1 klog -x saved lines" || bad "b1 no saved lines: $(grep -a 'saved' "$TMPD/b1.ser" | head -1)"
boot b2 "klog -a GATEMARK_TWO;klog -x;dmesg -p;exit"
grep -aq 'I prog: GATEMARK_ONE' "$TMPD/b2.ser" && ok "b2 dmesg -p shows the previous boot" || bad "b2 previous boot line missing"
grep -aq 'I prog: GATEMARK_TWO' "$TMPD/b2.ser" && bad "b2 -p shows the current boot" || ok "b2 -p excludes the current boot"

echo "== 2. kernel panic is persisted =="
boot b3 "klog -a GATEMARK_PANIC;krach kern;exit"
boot b4 "dmesg -p;exit"
grep -aq 'I prog: GATEMARK_PANIC' "$TMPD/b4.ser" && ok "b4 panic boot readable after reboot" || bad "b4 panic marker missing"

echo "== 3. filters =="
boot b5 "klog -a GATEMARK_FILTER;dmesg -n 5 -s prog -t;dmesg -l error;exit"
grep -aq '^GATEMARK_FILTER' "$TMPD/b5.ser" || grep -aq 'prog: GATEMARK_FILTER' "$TMPD/b5.ser" && ok "b5 -s prog -t shows the line" || bad "b5 filter output missing"

echo "== 4. rotation =="
boot b6 "klog -F 6000;exit"
bash tools/mkfsfi/mkfs.sh list "$IMG" > "$TMPD/list.txt" 2>&1
for f in klog klog.1 klog.2; do grep -aq "var/log/$f\b" "$TMPD/list.txt" && ok "segment $f exists" || bad "segment $f missing"; done
grep -aq "var/log/klog.4" "$TMPD/list.txt" && bad "klog.4 exists" || ok "at most 4 segments"
big=0
for f in klog klog.1 klog.2 klog.3; do
    n=$(bash tools/mkfsfi/mkfs.sh cat "$IMG" "/var/log/$f" 2>/dev/null | wc -c)
    [ "$n" -gt 270000 ] && big=1
done
[ "$big" = 0 ] && ok "no segment above 256 KiB + one chunk" || bad "segment too large"

if [ -n "${KLOGPERSIST_NOMUT:-}" ]; then echo "KLOGPERSIST: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit; fi
echo "== 5. counter-probe: no panic save =="
M="$TMPD/mut"; mkdir -p "$M"
tar -C "$(pwd)" --exclude=.git -cf - . | tar -C "$M" -xf -
sed -i 's/^    klogsave.panic_save(state)$//' "$M/kernel/diag/crash.fi"
if cmp -s "$M/kernel/diag/crash.fi" kernel/diag/crash.fi; then bad "mutant changed nothing"; else
    ( cd "$M" && bash tools/build-kernel.sh "$TMPD/km.mb" > "$TMPD/mbuild.log" 2>&1 ) || bad "mutant kernel build"
    K0="$TMPD/km.mb"
    bash tools/mkfsfi/mkfs.sh build "$IMG" 4096 $SPEC /proc/ /dev/ /mnt/ /var/ /var/crash/ > "$TMPD/mkfs2.txt" 2>&1
    boot m1 "klog -a GATEMARK_MUTPANIC;krach kern;exit"
    boot m2 "dmesg -p;exit"
    grep -aq 'I prog: GATEMARK_MUTPANIC' "$TMPD/m2.ser" && bad "mutant nopanicsave still shows marker" || ok "mutant nopanicsave goes red"
fi
echo "KLOGPERSIST: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
