#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
TMPD=$(mktemp -d)
trap 'git worktree remove --force "$TMPD/old" >/dev/null 2>&1; rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has()    { grep -qaF -- "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" 2>/dev/null && bad "$3 -- '$2' present" || ok "$3"; }
ACCEL=""
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then ACCEL="-accel kvm -cpu Skylake-Client,pmu=on"; fi
K0=${FSZAP_KERNEL:-}
if [ -z "$K0" ]; then
    bash tools/build-kernel.sh "$TMPD/k0.mb" > "$TMPD/build.log" 2>&1 || { bad "kernel build"; tail -5 "$TMPD/build.log"; exit 1; }
    K0="$TMPD/k0.mb"
fi
KOLD=${FSZAP_OLD_KERNEL:-}
if [ -z "$KOLD" ]; then
    git worktree add --detach "$TMPD/old" "${FSZAP_OLD_REF:-67190cba}" > /dev/null 2>&1 || bad "old worktree"
    ln -s "$(pwd)/vendor/firn/bin" "$TMPD/old/vendor/firn/bin"
    ln -s "$(pwd)/vendor/firn/lib" "$TMPD/old/vendor/firn/lib"
    (cd "$TMPD/old" && bash tools/build-kernel.sh "$TMPD/kold.mb" > "$TMPD/buildold.log" 2>&1) || bad "old kernel build"
    KOLD="$TMPD/kold.mb"
fi
as --64 -o "$TMPD/crt.o" kernel/user/crt.s || bad "crt.s"
PROGS="sh cat echo fsck"
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/e$p" 2>&1 || { bad "$p.fi compile"; head -5 "$TMPD/e$p"; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || bad "$p link"
done
printf 'scheme=day\nmode=dark\nshape=osum\nxx\n' > "$TMPD/theme.conf"
printf 'scheme=day\nmode=light\nshape=osum\n' > "$TMPD/theme.src"
printf 'lang=de\n' > "$TMPD/locale.conf"
TSIZE=$(stat -c %s "$TMPD/theme.conf")
SPEC="/bin/ /etc/ /tmp/ /etc/theme.conf=$TMPD/theme.conf /etc/locale.conf=$TMPD/locale.conf /tmp/theme.src=$TMPD/theme.src"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done

python3 tools/osum/mkfs.py build "$TMPD/base.img" 8192 --v3 $SPEC /proc/ /dev/ /mnt/ /var/ /var/crash/ > "$TMPD/mkfs.txt" 2>&1 || bad "mkfs"
qboot() {
    local img=$1 ser=$2 k=$3 script=$4
    timeout -s KILL 60 qemu-system-x86_64 $ACCEL -machine q35 -smp 2 -kernel "$k" -m 512 \
        -append "osum nokbd vfs smpfrueh script=$script;echo zapdone;exit" \
        -serial "file:$ser" -display none -global ICH9-LPC.noreboot=false \
        -drive "file=$img,format=raw,if=none,id=d0" -device ide-hd,drive=d0,bus=ide.0 \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 < /dev/null > /dev/null 2>&1
}
qboot "$TMPD/base.img" "$TMPD/warm.ser" "$K0" "echo warm"
grep -qax "zapdone" "$TMPD/warm.ser" && ok "warm-up boot created the boot-time files" || bad "warm-up boot"
python3 tools/fszap/plant.py "$TMPD/base.img" "$TSIZE" > "$TMPD/plant.txt" 2>&1 || bad "plant"
has "$TMPD/plant.txt" "planted" "garbage planted into the theme.conf inode"
INO=$(awk '/^planted/{print $2}' "$TMPD/plant.txt"); PARTNER=$(awk '/^planted/{print $4}' "$TMPD/plant.txt")
cp "$TMPD/base.img" "$TMPD/ctl.img"
qboot "$TMPD/ctl.img" "$TMPD/ctl.ser" "$K0" "echo idle"
python3 tools/fszap/check.py "$TMPD/base.img" "$TMPD/ctl.img" "$INO" > "$TMPD/ctl.chk" 2>&1
BOOTSET=$(awk '/^changed/{$1=""; print}' "$TMPD/ctl.chk" | tr ' ' '\n' | grep -v '^none$' | grep -v "^$")
expect_set() { printf '%s\n' $BOOTSET "$@" | grep -v '^$' | sort -n | uniq | tr '\n' ' ' | sed 's/ $//'; }
got_set() { awk '/^changed/{$1=""; print}' "$1" | tr ' ' '\n' | grep -v '^none$' | grep -v '^$' | sort -n | tr '\n' ' ' | sed 's/ $//'; }
has "$TMPD/ctl.chk" "bitmap same" "control boot leaves the bitmap alone"
echo "$BOOTSET" | grep -qx "$INO" && bad "control boot touched the planted inode" || ok "control boot leaves the planted inode (boot writes: $(echo $BOOTSET))"
boot() {
    local t=$1 k=$2 script=$3
    cp "$TMPD/base.img" "$TMPD/$t.img"
    qboot "$TMPD/$t.img" "$TMPD/$t.ser" "$k" "$script"
    python3 tools/fszap/check.py "$TMPD/base.img" "$TMPD/$t.img" "$INO" > "$TMPD/$t.chk" 2>&1
}

echo "== A. garbage inode: fsaudit names it, fsck zap resets only it, bitmap untouched =="
boot a "$K0" "cat /proc/fsaudit;fsck zap /etc/theme.conf $INO;cat /proc/fsaudit"
S=$TMPD/a.ser
grep -qax "zapdone" "$S" && ok "A script ran to the end" || bad "A zapdone missing"
has "$S" "bad $INO field 0 val" "A fsaudit reports the planted inode"
has "$S" "fsck: zap: inode reset $INO" "A fsck zap reports the reset"
has "$S" "fszap: inode reset $INO old type" "A kernel logs the reset with the old type"
[ "$(grep -ac '^scan_bad 0' "$S")" = 1 ] && ok "A fsaudit clean after the zap (exactly one scan_bad 0)" || bad "A scan_bad 0 count $(grep -ac '^scan_bad 0' "$S")"
[ "$(got_set "$TMPD/a.chk")" = "$(expect_set "$INO")" ] && ok "A only the planted inode changed (partner $PARTNER intact)" || bad "A changed: $(got_set "$TMPD/a.chk"), expected $(expect_set "$INO")"
has "$TMPD/a.chk" "bitmap same" "A block bitmap unchanged"
has "$TMPD/a.chk" "target type 1 size 0 nlink 1 ptrs zero" "A inode is an empty file without block pointers"

echo "== B. zap with template restores the content =="
boot b "$K0" "fsck zap /etc/theme.conf $INO /tmp/theme.src;cat /etc/theme.conf"
S=$TMPD/b.ser
grep -qax "zapdone" "$S" && ok "B script ran to the end" || bad "B zapdone missing"
has "$S" "fsck: zap: restored bytes $(stat -c %s "$TMPD/theme.src")" "B template copied"
has "$S" "mode=light" "B theme.conf reads the template"
python3 tools/osum/mkfs.py cat "$TMPD/b.img" /etc/theme.conf > "$TMPD/b.out" 2>/dev/null
cmp -s "$TMPD/b.out" "$TMPD/theme.src" && ok "B host reads the template from the disk" || bad "B host content differs"
[ "$(got_set "$TMPD/b.chk")" = "$(expect_set "$INO")" ] && ok "B no other inode changed" || bad "B changed: $(got_set "$TMPD/b.chk")"

echo "== C. wrong inode number: refused, disk untouched =="
boot c "$K0" "fsck zap /etc/theme.conf $PARTNER"
S=$TMPD/c.ser
has "$S" "fsck: zap: path names another inode $INO" "C mismatch refused by fsck"
[ "$(got_set "$TMPD/c.chk")" = "$(expect_set)" ] && ok "C no inode changed beyond the boot writes" || bad "C changed: $(got_set "$TMPD/c.chk")"
hasnot "$S" "fszap: inode reset" "C kernel did not reset anything"

echo "== D. counter-proof: kernel without the zap path leaves the garbage =="
boot d "$KOLD" "fsck zap /etc/theme.conf $INO"
S=$TMPD/d.ser
[ -s "$S" ] && ok "D old kernel booted" || bad "D no serial output"
has "$S" "fsck: zap: kernel refused" "D old kernel refuses the request"
[ "$(got_set "$TMPD/d.chk")" = "$(expect_set)" ] && ok "D garbage inode still there" || bad "D changed: $(got_set "$TMPD/d.chk")"
if [ -n "${FSZAP_OUT:-}" ]; then mkdir -p "$FSZAP_OUT"; cp "$TMPD"/*.ser "$TMPD"/*.chk "$TMPD"/plant.txt "$FSZAP_OUT/" 2>/dev/null; fi
echo
echo "FSZAP: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
