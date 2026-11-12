#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/tmpdir.sh
export FIRNLIB="$(pwd)/lib"
. tools/lib/firnenv.sh
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
printf 'aaa\n' > "$TMPD/f.txt"
SPEC="$SPEC /etc/alpha.txt=$TMPD/alpha.txt /etc/f.txt=$TMPD/f.txt"
bash tools/mkfsfi/mkfs.sh build "$TMPD/base.img" 8192 --v3 $SPEC > "$TMPD/mkfs.txt" 2>&1 || { bad "mkfs"; exit 1; }
qboot() {
    local t=$1 words=$2 script=$3
    cp "$TMPD/base.img" "$TMPD/$t.img"
    timeout -s KILL 90 qemu-system-x86_64 $ACCEL -machine q35 -smp 2 -kernel "$TMPD/k.mb" -m 512 \
        -append "osum nokbd vfs vfsall smpfrueh $words script=$script;echo vfsdone;exit" \
        -serial "file:$TMPD/$t.ser" -display none -global ICH9-LPC.noreboot=false \
        -drive "file=$TMPD/$t.img,format=raw,if=none,id=d0" -device ide-hd,drive=d0,bus=ide.0 \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 < /dev/null > /dev/null 2>&1
    tr -d '\r' < "$TMPD/$t.ser" > "$TMPD/$t.txt"
}
stat_of() { awk -v k="$2" '$1==k {v=$2} END {print v+0}' "$TMPD/$1.txt"; }
lines_of() { grep -ac "^$2\$" "$TMPD/$1.txt"; }
old_served() { awk '/^osum\$ mv ->/{f=1;next} /^\[after-old\]/{f=0} f' "$TMPD/$1.txt" | grep -ac '^alpha$'; }
done_ok() { grep -qax "vfsdone" "$TMPD/$1.txt" && ok "$2 script ran to the end" || bad "$2 vfsdone missing"; }
SCRIPT_D="cat /etc/alpha.txt;cat /etc/alpha.txt;cat /etc/nothere;cat /etc/nothere;mv /etc/alpha.txt /etc/beta.txt;cat /etc/alpha.txt;echo [after-old];cat /etc/beta.txt;echo [after-new];cat /proc/vfscache"
SCRIPT_N="cat /etc/new.txt;echo hi > /etc/new.txt;cat /etc/new.txt;cat /etc/new.txt;rm /etc/new.txt;cat /etc/new.txt;echo [gone];cat /proc/vfscache"
SCRIPT_P="cat /etc/f.txt;echo bbb > /etc/f.txt;cat /etc/f.txt;cat /etc/f.txt;cat /proc/vfscache"
echo "== A. default: both caches hit, rename and rewrite stay coherent =="
qboot a "" "$SCRIPT_D"
done_ok a A
[ "$(stat_of a dcache.hit)" -gt 0 ] && ok "A dentry cache hits $(stat_of a dcache.hit)" || bad "A no dentry hits"
[ "$(stat_of a dcache.neg)" -gt 0 ] && ok "A negative dentry hits $(stat_of a dcache.neg)" || bad "A no negative hits"
[ "$(stat_of a dcache.flush)" -gt 0 ] && ok "A rename flushed the dentry cache" || bad "A no flush after rename"
[ "$(lines_of a alpha)" = 3 ] && [ "$(old_served a)" = 0 ] && ok "A old name gone after rename, new name serves the data" || bad "A alpha lines $(lines_of a alpha), old name served $(old_served a)"
qboot p "" "$SCRIPT_P"
done_ok p AP
[ "$(stat_of p pcache.hit)" -gt 0 ] && ok "AP page cache hits $(stat_of p pcache.hit)" || bad "AP no page hits"
[ "$(lines_of p aaa)" = 1 ] && [ "$(lines_of p bbb)" -ge 2 ] && ok "AP rewrite visible through the page cache" || bad "AP aaa=$(lines_of p aaa) bbb=$(lines_of p bbb)"
echo "== B. counter-proof dcnoinval: stale dentry after rename =="
qboot b "dcnoinval" "$SCRIPT_D"
done_ok b B
[ "$(old_served b)" -ge 1 ] && ok "B stale dentry still serves the old name" || bad "B no stale read, counter-proof inactive"
echo "== C. counter-proof pcnoinval: stale page after rewrite =="
qboot q "pcnoinval" "$SCRIPT_P"
done_ok q C
[ "$(lines_of q aaa)" -gt 1 ] && ok "C stale page serves the old data" || bad "C no stale read, counter-proof inactive"
echo "== D. counter-proof nodcache: no dentry traffic, same data =="
qboot c "nodcache" "$SCRIPT_D"
done_ok c D
[ "$(stat_of c dcache.hit)" = 0 ] && [ "$(stat_of c dcache.insert)" = 0 ] && ok "D no dentry hits or inserts" || bad "D dentry cache active"
[ "$(lines_of c alpha)" = 3 ] && ok "D same data as default" || bad "D differs"
echo "== E. counter-proof nopcache: no page traffic, same data =="
qboot n "nopcache" "$SCRIPT_P"
done_ok n E
[ "$(stat_of n pcache.hit)" = 0 ] && [ "$(stat_of n pcache.insert)" = 0 ] && ok "E no page hits or inserts" || bad "E page cache active"
[ "$(lines_of n aaa)" = 1 ] && [ "$(lines_of n bbb)" -ge 2 ] && ok "E same data as default" || bad "E differs"
echo "== F. create and unlink of a file invalidate only that name =="
qboot f "" "$SCRIPT_N"
done_ok f F
hi_after_gone() { awk '/^\[gone\]/{f=1;next} f' "$TMPD/$1.txt" | grep -ac '^hi$'; }
[ "$(lines_of f hi)" = 2 ] && [ "$(hi_after_gone f)" = 0 ] && ok "F created file visible after a negative entry, gone after rm" || bad "F hi lines $(lines_of f hi), after rm $(hi_after_gone f)"
[ "$(stat_of f dcache.name)" -gt 0 ] && [ "$(stat_of f dcache.node)" -gt 0 ] && ok "F targeted invalidation by name and by node" || bad "F name=$(stat_of f dcache.name) node=$(stat_of f dcache.node)"
[ "$(stat_of f dcache.full)" -le 10 ] && ok "F no full flush for create and unlink ($(stat_of f dcache.full))" || bad "F full flushes $(stat_of f dcache.full)"
echo
if [ -n "${VFSCACHE_OUT:-}" ]; then mkdir -p "$VFSCACHE_OUT"; cp "$TMPD"/*.ser "$VFSCACHE_OUT/" 2>/dev/null; fi
echo "VFSCACHE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
