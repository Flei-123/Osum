#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/startcrash/run.sh -- a crashing bundle app is reported under its app name, and a program built before the
# ARGS_BASE move (argument block at 0x4007F000) still starts.
#
#   /root/jarvis/bin/heavy bash tools/startcrash/run.sh
#
# A  /apps/segv.osp/start (hard link of /bin/segv) dies: /var/crash/<n>.txt says `prog:  segv`, never `prog:  start`.
# B  /apps/oldopen.osp/start is argsprobe (profile app) built with ulib.ARGS_BASE = 0x4007F000: it prints `argsprobe argc=1` (argc read from
#    the legacy argument page), no crash report.
# C  counter-proof `nolegacyargs`: the same binary dies at cr2 0x4007f000 (the HP crash), report names it `oldopen`.
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
K0=${STARTCRASH_KERNEL:-}
if [ -z "$K0" ]; then
    bash tools/build-kernel.sh "$TMPD/k0.mb" --stufe 0 > "$TMPD/build.log" 2>&1 || { bad "kernel build"; tail -5 "$TMPD/build.log"; exit 1; }
    K0="$TMPD/k0.mb"
fi
as --64 -o "$TMPD/crt.o" kernel/user/crt.s || bad "crt.s"
mkdir -p "$TMPD/oldsrc"
cp -r kernel/user/. "$TMPD/oldsrc/"
sed -i 's/^const ARGS_BASE: u64 = 0x535FF000/const ARGS_BASE: u64 = 0x4007F000/' "$TMPD/oldsrc/ulib.fi"
grep -q '0x4007F000' "$TMPD/oldsrc/ulib.fi" || bad "ulib.fi patch for the old argument page"
build() { # <out name> <source dir> <program>
    "$FIRNC" "$2/$3.fi" -o "$TMPD/$1.o" > "$TMPD/e$1" 2>&1 || { bad "$3.fi compile"; head -5 "$TMPD/e$1"; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$TMPD/$1.elf" "$TMPD/crt.o" "$TMPD/$1.o" 2>/dev/null || bad "$1 link"
}
for p in sh ls cat echo segv; do build "$p" kernel/user "$p"; done
"$FIRNC" --profile=app -c "$TMPD/oldsrc/argsprobe.fi" -o "$TMPD/oldopen.o" > "$TMPD/eoldopen" 2>&1 || { bad "argsprobe.fi compile"; head -5 "$TMPD/eoldopen"; }
ld -T kernel/user/user.ld -o "$TMPD/oldopen.elf" "$TMPD/oldopen.o" 2>/dev/null || bad "oldopen link"
SPEC="/bin/ /apps/ /apps/segv.osp/ /apps/oldopen.osp/"
for p in sh ls cat echo segv oldopen; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
SPEC="$SPEC /apps/segv.osp/start@/bin/segv /apps/oldopen.osp/start@/bin/oldopen"
SCRIPT="script=/apps/segv.osp/start;/apps/oldopen.osp/start;exit"

boot() { # <tag> <extra words>
    local t=$1 img="$TMPD/$1.img"
    bash tools/mkfsfi/mkfs.sh build "$img" 4096 $SPEC /proc/ /dev/ /mnt/ /var/ /var/crash/ > "$TMPD/mkfs-$t.txt" 2>&1 || bad "$t mkfs"
    timeout 90 qemu-system-x86_64 $ACCEL -kernel "$K0" -m 256 -append "osum nokbd vfs $2 $SCRIPT" -serial "file:$TMPD/$t.ser" -display none -no-reboot \
        -drive "file=$img,format=raw,if=none,id=nv" -device nvme,drive=nv,serial=sc93 \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
}
reports() { # <tag>: all crash reports of the image, concatenated
    local t=$1 f
    for f in $(bash tools/mkfsfi/mkfs.sh list "$TMPD/$t.img" 2>/dev/null | grep -oE "var/crash/[0-9]+\.txt" | sed "s,.*/,,"); do
        bash tools/mkfsfi/mkfs.sh cat "$TMPD/$t.img" "/var/crash/$f" 2>/dev/null
    done > "$TMPD/$t.rep"
}

echo "== A+B. fixed kernel =="
boot a ""
reports a
grep -aq 'prog:  segv' "$TMPD/a.rep" && ok "A report names the bundle app: segv" || bad "A report prog line: $(grep -a 'prog:' "$TMPD/a.rep" | head -2 | tr '\n' ' ')"
grep -aq 'prog:  start' "$TMPD/a.rep" && bad "A a report still says 'start'" || ok "A no report says 'start'"
grep -aq 'argsprobe argc=1' "$TMPD/a.ser" && ok "B old-ABI program ran and read its argument block" || bad "B no usage line from oldopen"
grep -aq 'prog:  oldopen' "$TMPD/a.rep" && bad "B old-ABI program crashed" || ok "B old-ABI program left no crash report"

echo "== C. counter-proof nolegacyargs =="
boot c "nolegacyargs"
reports c
grep -aq 'prog:  oldopen' "$TMPD/c.rep" && ok "C without the legacy page the program dies and is named oldopen" || bad "C no oldopen report: $(grep -a 'prog:' "$TMPD/c.rep" | head -2 | tr '\n' ' ')"
grep -aq 'cr2 0x000000004007f000' "$TMPD/c.rep" && ok "C fault address is the old argument page (0x4007f000), as in the HP dump" || bad "C cr2 is not 0x4007f000"
grep -aq 'argsprobe argc=1' "$TMPD/c.ser" && bad "C usage line printed without the legacy page" || ok "C no usage line without the legacy page"
if [ -n "${STARTCRASH_OUT:-}" ]; then mkdir -p "$STARTCRASH_OUT"; cp "$TMPD"/*.ser "$TMPD"/*.rep "$STARTCRASH_OUT/" 2>/dev/null; fi
echo "startcrash: $pass/$fail OK/FAIL"
[ "$fail" -eq 0 ]
