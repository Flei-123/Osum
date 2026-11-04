#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/tmpdir.sh
export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
TMPD=$(mktemp -d)
osum_tmp_guard "${1:-}" "$TMPD"
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has()    { grep -qaF -- "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" 2>/dev/null && bad "$3 -- '$2' present" || ok "$3"; }
ACCEL=""
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then ACCEL="-accel kvm -cpu Skylake-Client,pmu=on"; fi
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/build.log" 2>&1 || { bad "kernel build"; tail -5 "$TMPD/build.log"; exit 1; }
as --64 -o "$TMPD/crt.o" kernel/user/crt.s || bad "crt.s"
PROGS="sh cat echo mv rm"
SPEC="/bin/ /etc/ /tmp/ /proc/ /dev/ /mnt/ /var/"
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/e$p" 2>&1 || { bad "$p.fi compile"; head -3 "$TMPD/e$p"; continue; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || bad "$p link"
    SPEC="$SPEC /bin/$p=$TMPD/$p.elf"
done
printf 'alpha\n' > "$TMPD/alpha.txt"
SPEC="$SPEC /etc/alpha.txt=$TMPD/alpha.txt"
bash tools/mkfsfi/mkfs.sh build "$TMPD/base.img" 8192 --v3 $SPEC > "$TMPD/mkfs.txt" 2>&1 || { bad "mkfs"; exit 1; }
qboot() {
    local t=$1 words=$2 script=$3
    cp "$TMPD/base.img" "$TMPD/$t.img"
    timeout -s KILL 90 qemu-system-x86_64 $ACCEL -machine q35 -smp 2 -kernel "$TMPD/k.mb" -m 512 \
        -append "osum nokbd vfs smpfrueh $words script=$script;echo vfsdone;exit" \
        -serial "file:$TMPD/$t.ser" -display none -global ICH9-LPC.noreboot=false \
        -drive "file=$TMPD/$t.img,format=raw,if=none,id=d0" -device ide-hd,drive=d0,bus=ide.0 \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 < /dev/null > /dev/null 2>&1
}
SCRIPT="cat /etc/alpha.txt;cat /etc/nothere;mv /etc/alpha.txt /etc/beta.txt;cat /etc/alpha.txt;echo [after-rename-old];cat /etc/beta.txt;echo [after-rename-new]"
qboot w "" "echo warm"
echo "== A. default: rename invalidates the dentry =="
qboot a "" "$SCRIPT"
grep -qax "vfsdone" "$TMPD/a.ser" \
    && ok "A script ran to the end" || bad "A vfsdone missing"
: has "$TMPD/a.ser" "vfsdone" "A script ran to the end"
[ "$(grep -ac '^alpha$' "$TMPD/a.ser")" = 2 ] && ok "A alpha read before rename and via new name only" || bad "A alpha count $(grep -ac '^alpha$' "$TMPD/a.ser")"
echo "== B. counter-proof dcnoinval: stale dentry after rename =="
qboot b "dcnoinval" "$SCRIPT"
grep -qax "vfsdone" "$TMPD/b.ser" && ok "B script ran to the end" || bad "B vfsdone missing"
[ "$(grep -ac '^alpha$' "$TMPD/b.ser")" -gt 2 ] && ok "B stale dentry still serves the old name" || bad "B no stale read (counter-proof inactive)"
echo "== C. nodcache/nopcache controls match default =="
qboot c "nodcache nopcache" "$SCRIPT"
[ "$(grep -ac '^alpha$' "$TMPD/c.ser")" = 2 ] && ok "C caches off: same result as default" || bad "C differs"
echo
if [ -n "${VFSCACHE_OUT:-}" ]; then mkdir -p "$VFSCACHE_OUT"; cp "$TMPD"/*.ser "$VFSCACHE_OUT/" 2>/dev/null; fi
echo "VFSCACHE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
