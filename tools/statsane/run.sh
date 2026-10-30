#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has()    { grep -qaF -- "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" 2>/dev/null && bad "$3 -- '$2' present" || ok "$3"; }
ACCEL=""
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then ACCEL="-accel kvm -cpu Skylake-Client,pmu=on"; fi
K0=${STATSANE_KERNEL:-}
if [ -z "$K0" ]; then
    bash tools/build-kernel.sh "$TMPD/k0.mb" > "$TMPD/build.log" 2>&1 || { bad "kernel build"; tail -5 "$TMPD/build.log"; exit 1; }
    K0="$TMPD/k0.mb"
fi
as --64 -o "$TMPD/crt.o" kernel/user/crt.s || bad "crt.s"
PROGS="sh ls cat echo chown"
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/e$p" 2>&1 || { bad "$p.fi compile"; head -5 "$TMPD/e$p"; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null || bad "$p link"
done
printf 'scheme=day\nmode=light\n' > "$TMPD/theme.conf"
SPEC="/bin/ /etc/ /etc/theme.conf=$TMPD/theme.conf"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
SCRIPT="script=chown 4294967296:4294967297 /etc/theme.conf;ls -l /etc/theme.conf;cat /etc/theme.conf;echo statdone;exit"

boot() {
    local t=$1 img="$TMPD/$1.img"
    python3 tools/osum/mkfs.py build "$img" 4096 $SPEC /proc/ /dev/ /mnt/ /var/ /var/crash/ > "$TMPD/mkfs-$t.txt" 2>&1 || bad "$t mkfs"
    timeout -s KILL "$3" qemu-system-x86_64 $ACCEL -machine q35 -smp 2 -kernel "$K0" -m 512 \
        -append "osum nokbd vfs smpfrueh wdt=10 $2 $SCRIPT" \
        -serial "file:$TMPD/$t.ser" -display none -global ICH9-LPC.noreboot=false -watchdog-action reset \
        -drive "file=$img,format=raw,if=none,id=d0" -device ide-hd,drive=d0,bus=ide.0 \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 < /dev/null > /dev/null 2>&1
}

crash_file() {
    python3 tools/osum/mkfs.py list "$1" 2>/dev/null | grep -oE "var/crash/[0-9]+[^ ]*\.txt" | head -1
}

echo "== A. inode with uid/gid above 32 bit on an AHCI root: stat survives =="
boot a "" 60
S=$TMPD/a.ser
grep -qax "statdone" "$S" && ok "A script ran past ls -l and cat" || bad "A statdone line missing"
has "$S" "mode=light" "A theme.conf content readable"
has "$S" "22 /etc/theme.conf" "A ls -l lists the file with its size"
has "$S" "inode, raw uid (bad)" "A kernel log names the bad inode field"
hasnot "$S" "panic: integer overflow" "A no checked-arithmetic panic"
f=$(crash_file "$TMPD/a.img")
[ -z "$f" ] && ok "A no crash report on disk" || bad "A crash report on disk: $f"

echo "== B. counter-proof nostatsane: the old cast panics, the hang report names it =="
boot b "nostatsane" 90
S=$TMPD/b.ser
grep -qax "statdone" "$S" && bad "B statdone printed" || ok "B script stops at the stat"
has "$S" "panic: integer overflow casting 'u64 as u32' at kernel/sys/sys.fi" "B COM1 shows the checked-cast panic"
f=$(crash_file "$TMPD/b.img")
if [ -n "$f" ]; then
    python3 tools/osum/mkfs.py cat "$TMPD/b.img" "/$f" 2>/dev/null | tr -cd '\11\12\15\40-\176' > "$TMPD/b.rep"
    has "$TMPD/b.rep" "reason: hard-peer" "B hang report: hard-peer"
    has "$TMPD/b.rep" "panic-text: panic: integer overflow casting 'u64 as u32'" "B hang report carries the panic text"
    has "$TMPD/b.rep" " ops=0x0000000100000000" "B hang report carries the operand"
else
    bad "B no hang report on disk"
fi
echo "== C. garbage mtime (HP inode 151): ls -l prints and returns; old ls spins =="
OLD_LS_REF=${STATSANE_OLD_LS_REF:-5376dedf}
mkdir -p "$TMPD/olduser"
for f in kernel/user/*.fi; do ln -s "$(pwd)/$f" "$TMPD/olduser/"; done
rm -f "$TMPD/olduser/ls.fi"
git show "$OLD_LS_REF:kernel/user/ls.fi" > "$TMPD/olduser/ls.fi" 2>/dev/null
"$FIRNC" "$TMPD/olduser/ls.fi" -o "$TMPD/lsold.o" > "$TMPD/elsold" 2>&1 && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$TMPD/lsold.elf" "$TMPD/crt.o" "$TMPD/lsold.o" 2>/dev/null || { bad "C old ls build"; head -5 "$TMPD/elsold"; }
SCRIPT="script=ls -l /etc/theme.conf;echo statdone;exit"
mtime_boot() {
    local t=$1 lself=$2 img="$TMPD/$1.img" spec="/bin/ /etc/ /etc/theme.conf=$TMPD/theme.conf"
    for p in sh cat echo chown; do spec="$spec /bin/$p=$TMPD/$p.elf"; done
    spec="$spec /bin/ls=$lself"
    python3 tools/osum/mkfs.py build "$img" 8192 --v3 $spec /proc/ /dev/ /mnt/ /var/ /var/crash/ > /dev/null 2>&1 || bad "$t mkfs"
    python3 tools/statsane/plant_mtime.py "$img" 22 0x04c7c74820244c89 > "$TMPD/$t.plant" 2>&1 || bad "$t plant mtime"
    timeout -s KILL 45 qemu-system-x86_64 $ACCEL -machine q35 -smp 2 -kernel "$K0" -m 512 \
        -append "osum nokbd vfs smpfrueh wdt=10 $SCRIPT" \
        -serial "file:$TMPD/$t.ser" -display none -global ICH9-LPC.noreboot=false -watchdog-action reset \
        -drive "file=$img,format=raw,if=none,id=d0" -device ide-hd,drive=d0,bus=ide.0 \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 < /dev/null > /dev/null 2>&1
}
mtime_boot c "$TMPD/ls.elf"
has "$TMPD/c.plant" "planted" "C mtime planted into the inode"
grep -qax "statdone" "$TMPD/c.ser" && ok "C ls -l returned with a garbage mtime" || bad "C statdone missing"
has "$TMPD/c.ser" " /etc/theme.conf" "C ls -l printed the line"
mtime_boot d "$TMPD/lsold.elf"
has "$TMPD/d.plant" "planted" "D mtime planted into the inode"
[ -s "$TMPD/d.ser" ] && ok "D kernel booted" || bad "D no serial output"
grep -qax "statdone" "$TMPD/d.ser" && bad "D old ls returned (counter-proof did not bite)" || ok "D counter-proof: old ls spins on the garbage mtime"
if [ -n "${STATSANE_OUT:-}" ]; then mkdir -p "$STATSANE_OUT"; cp "$TMPD"/*.ser "$TMPD"/*.rep "$STATSANE_OUT/" 2>/dev/null; fi
echo
echo "STATSANE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
