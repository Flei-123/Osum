#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/usbexfat/run.sh -- gate for USB mass storage + exFAT automount + safe eject (R-012).
#
#   /root/jarvis/bin/heavy bash tools/usbexfat/run.sh
#
# MEASURES (QEMU `-device qemu-xhci`, usb-storage sticks hot-plugged over the monitor):
#   1. exFAT stick (MBR table) appears while the machine runs: automount, files made by the
#      host reference writer are read back with identical SHA-256, Osum writes (mkdir, create,
#      copy, rename, delete), `eject` flushes and sends SYNCHRONIZE CACHE; the host then reads
#      the stick with exfat.py and fsck.exfat -n must call it clean.
#   2. exFAT + FAT32 stick at the same time: both mounted, no cross-talk, both ejected.
#   3. exFAT without a partition table (super-floppy) is mounted too; pulling it without eject
#      must not stop the kernel; plugging it again mounts it again.
#   4. files above 4 GiB (contiguous and FAT-chained) on a 12 GiB sparse stick: reads at offsets
#      beyond 4 GiB give the host's marker bytes, an append grows the file, fsck.exfat is clean.
#   5. corrupted exFAT images (boot sector, directory sets, FAT chains, bitmap): the kernel must
#      neither crash nor hang, and must finish its script.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
PROGS="sh cat echo ls cp rm rmdir mkdir mv wc shasum mount umount eject head sleep"
FUZZ_COUNT=${FUZZ_COUNT:-12}
PY="python3 -I tools/exfat/exfat.py"
BIG_SIZE=4600000000
PART_OFF=$((2048 * 512))

ARB=${UX_ARB:-$(mktemp -d)}
mkdir -p "$ARB"
export ARB
[ -n "${UX_ARB:-}" ] || trap 'rm -rf "$ARB"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' missing"; }
has_not() { grep -qaF "$2" "$1" 2>/dev/null && bad "$3 -- '$2' present" || ok "$3"; }
num() {
    if [ -z "${2:-}" ]; then bad "$1: no number (expected $3 $4)"; return; fi
    if [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"; else bad "$1: $2, expected $3 $4"; fi
}

for w in mkfs.exfat fsck.exfat mkfs.vfat mcopy mdir mtype sfdisk qemu-system-x86_64 python3; do
    command -v "$w" >/dev/null 2>&1 || { echo "USBEXFAT: skipped, $w missing"; exit 0; }
done
qemu-system-x86_64 -device help 2>&1 | grep -q 'qemu-xhci' || { echo "USBEXFAT: skipped, no qemu-xhci"; exit 0; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { [ -x "$FIRNC" ] || { echo "USBEXFAT: no firnc"; exit 1; }; }

echo "== 1. build: kernel, programs, root disk =="
KERN="$ARB/k.mb"
./tools/build-kernel.sh "$KERN" > "$ARB/build.log" 2>&1 \
    && ok "kernel built ($(stat -c%s "$KERN") bytes)" \
    || { bad "kernel does not build"; tail -8 "$ARB/build.log"; echo "USBEXFAT: $pass passed, $fail failed"; exit 1; }

as --64 -o "$ARB/crt.o" kernel/user/crt.s 2>/dev/null
MK=""
build_prog() { # src name
    if "$FIRNC" "$1" -o "$ARB/$2.o" > "$ARB/$2.log" 2>&1 \
       && ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" -o "$ARB/$2" "$ARB/crt.o" "$ARB/$2.o" 2>>"$ARB/$2.log"; then
        MK="$MK /bin/$2=$ARB/$2"
    else
        bad "$2 does not build"; grep -E '^error' "$ARB/$2.log" | head -3 | sed 's/^/        /'
    fi
}
for p in $PROGS; do [ -f "kernel/user/$p.fi" ] && build_prog "kernel/user/$p.fi" "$p"; done
mkdir -p "$ARB/prog"
cp tools/usbexfat/prog/readat.fi "$ARB/prog/readat.fi"
ln -sf "$ROOT/kernel/user/ulib.fi" "$ARB/prog/ulib.fi"
build_prog "$ARB/prog/readat.fi" readat
ok "programs built"

python3 -I - "$ARB/src.bin" <<'PYEOF'
import sys
sys.path.insert(0, "tools/exfat")
import exfat
open(sys.argv[1], "wb").write(exfat.pattern(1000000, 99))
PYEOF
SRC_SHA=$(python3 -I tools/usbexfat/cmp.py sha "$ARB/src.bin")

make_root() { # name script
    python3 tools/osum/mkfs.py build "$ARB/root-$1.img" 20000 /bin/ /proc/ /dev/ /mnt/ /usb/ /medien/ /t/ $MK \
        "/src.bin=$ARB/src.bin" "/t/s.sh=$2" > "$ARB/mkfs-$1.log" 2>&1 \
        || { bad "mkfs.py for $1"; tail -3 "$ARB/mkfs-$1.log"; return 1; }
}

mbr_disk() { # fsimg disk
    local mib=$(( $(stat -c %s "$1") / 1048576 + 2 ))
    rm -f "$2"; dd if=/dev/null of="$2" bs=1M seek=$mib 2>/dev/null
    printf 'label: dos\nstart=2048, type=7\n' | sfdisk "$2" >/dev/null 2>&1
    dd if="$1" of="$2" bs=512 seek=2048 conv=notrunc status=none
}
extract_fs() { # disk fsimg bytes
    dd if="$1" of="$2" bs=512 skip=2048 count=$(( $3 / 512 )) status=none
}
exfat_fs() { # fsimg mib cluster
    rm -f "$1"; dd if=/dev/null of="$1" bs=1M seek="$2" 2>/dev/null
    mkfs.exfat -c "$3" "$1" >/dev/null 2>&1
}

echo
echo "== 2. images =="
FS_A="$ARB/a.fs"; DISK_A="$ARB/stickA.img"
exfat_fs "$FS_A" 40 4096 && $PY populate "$FS_A" 0 > "$ARB/a.base" 2>"$ARB/a.perr" \
    && fsck.exfat -n "$FS_A" >/dev/null 2>&1 \
    && ok "exFAT stick A: mkfs.exfat + reference tree ($(wc -l < "$ARB/a.base") entries), fsck clean" \
    || bad "stick A could not be made"
mbr_disk "$FS_A" "$DISK_A"

FS_F="$ARB/f.fs"; DISK_F="$ARB/stickF.img"
exfat_fs "$FS_F" 24 512 && $PY populate "$FS_F" 0 > "$ARB/f.base" 2>"$ARB/f.perr" \
    && ok "exFAT super-floppy F (512-byte clusters, no partition table)" || bad "stick F could not be made"
cp --sparse=always "$FS_F" "$DISK_F"

DISK_V="$ARB/stickV.img"
rm -f "$DISK_V"; dd if=/dev/zero of="$DISK_V" bs=1M count=48 status=none
printf 'label: dos\nstart=2048, type=c\n' | sfdisk "$DISK_V" >/dev/null 2>&1
dd if=/dev/zero of="$ARB/v.part" bs=1M count=46 status=none
mkfs.vfat -F32 -n STICKV "$ARB/v.part" >/dev/null 2>&1
printf 'fat32-side\n' > "$ARB/v.host"
mcopy -i "$ARB/v.part" "$ARB/v.host" ::host.txt
dd if="$ARB/v.part" of="$DISK_V" bs=512 seek=2048 conv=notrunc status=none
rm -f "$ARB/v.part"
ok "FAT32 stick V next to it"

FS_B="$ARB/b.fs"; DISK_B="$ARB/stickB.img"
exfat_fs "$FS_B" 12288 32768
python3 -I tools/usbexfat/bigfile.py "$FS_B" 0 "$BIG_SIZE" > "$ARB/big.log" 2>&1 \
    && fsck.exfat -n "$FS_B" > "$ARB/big.fsck0" 2>&1 \
    && ok "12 GiB sparse stick B with two $BIG_SIZE-byte files (contiguous + FAT chain), fsck clean" \
    || { bad "stick B could not be made"; tail -3 "$ARB/big.log"; tail -3 "$ARB/big.fsck0"; }
mv "$FS_B" "$DISK_B"

run_case() { # name kernel-words script-file drehbuch [qemu-args...]
    local name=$1 words=$2 script=$3 dreh=$4
    shift 4
    make_root "$name" "$script" || { RC=99; return; }
    HP_TIMEOUT=${HP_TIMEOUT:-300} ARB="$ARB" \
        bash tools/hotplug/lauf.sh "$name" "$KERN" "$words" "$dreh" \
        -drive "file=$ARB/root-$name.img,format=raw,if=ide,index=0" \
        -device qemu-xhci,id=xhci "$@" > "$ARB/$name.lauf" 2>&1 < /dev/null
    RC=$(sed -n 's/^RC=//p' "$ARB/$name.lauf" | tail -1)
    tr -d '\r\000' < "$ARB/$name.txt" > "$ARB/$name.out" 2>/dev/null
}
WORDS="osum usb usbhold vfs gfx nosched noproc script=sh /t/s.sh;exit"
U=/medien/usb0

echo
echo "== 3. exFAT stick appears at run time: automount, read, write, eject =="
{
    echo 'echo @@ls'
    echo "ls $U"
    echo "ls $U/sub"
    echo 'echo @@sums'
    grep -v '^-' "$ARB/a.base" | sed -E 's|^[0-9a-f]{64} [0-9]+ |"'"$U"'|; s|$|"|' \
        | awk 'NR%5==1{printf "shasum"} {printf " %s", $0} NR%5==0{print ""} END{if (NR%5) print ""}'
    echo 'echo @@write'
    echo "mkdir $U/w"
    echo "echo hello-from-osum > $U/w/new.txt"
    echo "cp /src.bin $U/w/src.bin"
    echo "cp $U/big.bin $U/w/bigcopy.bin"
    echo "cp $U/many/file05.txt $U/w/over.txt"
    echo "echo short > $U/w/over.txt"
    echo "mv $U/frag.bin $U/w/moved.bin"
    echo "rm $U/hello.txt"
    echo "mkdir $U/w/long"
    echo "echo x > $U/w/long/a-rather-long-file-name-over-fifteen-chars.bin"
    echo "echo umlaut-test > \"$U/w/Übung-äöü-ßé.txt\""
    echo "shasum \"$U/w/ÜBUNG-ÄÖÜ-ßÉ.txt\""
    echo "echo greek-cyr > \"$U/w/αβγ-Привет.txt\""
    echo 'echo @@readback'
    echo "shasum $U/w/src.bin $U/w/bigcopy.bin $U/w/moved.bin $U/w/new.txt $U/w/over.txt"
    echo 'echo @@eject'
    echo 'eject 0'
    echo 'echo @@end'
} > "$ARB/s-a.sh"
cat > "$ARB/dreh-a.txt" <<EOF
aufzeile k17: hold
warte 1
stecke stkA $DISK_A
aufzeile wechsel: kommt
warte 2
EOF
t0=$SECONDS
run_case rw "$WORDS" "$ARB/s-a.sh" "$ARB/dreh-a.txt"
num "kernel finished by itself (21), $((SECONDS - t0)) s" "${RC:-99}" eq 21
S="$ARB/rw.out"
has "$S" "wechsel: kommt" "the join sees the stick"
grep -aq 'fs=7' "$S" && ok "detected as exFAT (fs=7) from the boot sector" || bad "fs=7 missing"
has "$S" "exfat: spc=" "exFAT mounted"
has "$S" "mount=1" "and registered under /medien/usb0"
python3 -I tools/usbexfat/cmp.py sums "$ARB/a.base" "$S" "$U" > "$ARB/rw.cmp" 2>&1 \
    && ok "every host-written file reads back with the same SHA-256 ($(cat "$ARB/rw.cmp"))" \
    || { bad "read-back differs: $(cat "$ARB/rw.cmp")"; }
has "$S" "ejected: " "eject answers"
has "$S" "usb: msc sync ok=1" "SYNCHRONIZE CACHE sent and accepted at eject"
extract_fs "$DISK_A" "$ARB/a.after" $((40 * 1048576))
if fsck.exfat -n "$ARB/a.after" > "$ARB/a.fsck1" 2>&1; then ok "fsck.exfat: stick is clean after Osum wrote and ejected"
else bad "fsck.exfat finds damage after Osum wrote"; sed 's/^/        /' "$ARB/a.fsck1" | head -6; fi
$PY dump "$ARB/a.after" 0 > "$ARB/a.dump" 2>"$ARB/a.derr"
HELLO_SHA=$(printf 'hello-from-osum\n' | sha256sum | cut -d' ' -f1)
BIG_SHA=$(grep ' /big.bin$' "$ARB/a.base" | cut -d' ' -f1)
FRAG_SHA=$(grep ' /frag.bin$' "$ARB/a.base" | cut -d' ' -f1)
python3 -I tools/usbexfat/cmp.py tree "$ARB/a.dump" \
    "/w/new.txt=$HELLO_SHA" "/w/src.bin=$SRC_SHA" "/w/bigcopy.bin=$BIG_SHA" "/w/moved.bin=$FRAG_SHA" \
    "/w/Übung-äöü-ßé.txt=$(printf 'umlaut-test\n' | sha256sum | cut -d' ' -f1)" \
    "/w/αβγ-Привет.txt=$(printf 'greek-cyr\n' | sha256sum | cut -d' ' -f1)" \
    "/hello.txt=absent" "/frag.bin=absent" > "$ARB/a.tree" 2>&1 \
    && ok "host reads what Osum wrote: create, 1 MB copy, in-fs copy, rename, delete, long name dir" \
    || { bad "host read-back of Osum's writes differs"; cat "$ARB/a.tree" | head -8; }
has "$S" "$(printf 'umlaut-test\n' | sha256sum | cut -d' ' -f1)" "case-insensitive lookup of a non-ASCII name (ÜBUNG finds Übung)"
grep -q 'a-rather-long-file-name-over-fifteen-chars.bin' "$ARB/a.dump" \
    && ok "a 48-character name written by Osum is read by the host" || bad "long name missing on the host"

echo
echo "== 4. exFAT + FAT32 at the same time =="
{
    echo "ls /medien/usb0"
    echo "ls /medien/usb1"
    echo "cat /medien/usb1/host.txt"
    echo "echo from-usb0 > /medien/usb0/z0.txt"
    echo "echo from-usb1 > /medien/usb1/z1.txt"
    echo 'eject 0'
    echo 'eject 1'
    echo 'echo @@end'
} > "$ARB/s-two.sh"
cp --sparse=always "$DISK_A" "$ARB/stickA2.img"
cat > "$ARB/dreh-two.txt" <<EOF
aufzeile k17: hold
warte 1
stecke stkX $ARB/stickA2.img
aufzeile wechsel: kommt
warte 2
stecke stkY $DISK_V
warte 8
EOF
run_case two "$WORDS" "$ARB/s-two.sh" "$ARB/dreh-two.txt"
S="$ARB/two.out"
num "kernel finished by itself (21)" "${RC:-99}" eq 21
n=$(grep -ac 'wechsel: kommt' "$S"); num "both sticks mounted" "${n:-0}" eq 2
has "$S" "fat32-side" "FAT32 stick readable next to the exFAT one"
n=$(grep -ac 'ejected: ' "$S"); num "both ejected" "${n:-0}" ge 2
extract_fs "$ARB/stickA2.img" "$ARB/a2.after" $((40 * 1048576))
$PY dump "$ARB/a2.after" 0 > "$ARB/a2.dump" 2>/dev/null
python3 -I tools/usbexfat/cmp.py tree "$ARB/a2.dump" "/z0.txt=$(printf 'from-usb0\n' | sha256sum | cut -d' ' -f1)" "/z1.txt=absent" > "$ARB/a2.tree" 2>&1 \
    && ok "z0.txt is on the exFAT stick and z1.txt is not (no cross-talk)" || { bad "cross-talk or missing file"; cat "$ARB/a2.tree"; }
OFF=$PART_OFF
mdir -i "$DISK_V@@$OFF" ::z1.txt >/dev/null 2>&1 && ok "z1.txt is on the FAT32 stick" || bad "z1.txt missing on FAT32 stick"
fsck.exfat -n "$ARB/a2.after" >/dev/null 2>&1 && ok "fsck.exfat clean on the first stick" || bad "fsck.exfat damage on the first stick"

echo
echo "== 5. super-floppy exFAT; pull without eject; plug it again =="
{
    echo "ls /medien/usb0"
    echo "cat /medien/usb0/hello.txt"
    echo "sleep 6"
    echo "ls /medien/usb0"
    echo 'echo @@end'
} > "$ARB/s-pull.sh"
cp --sparse=always "$DISK_F" "$ARB/stickF2.img"
cp --sparse=always "$DISK_F" "$ARB/stickF3.img"
cat > "$ARB/dreh-pull.txt" <<EOF
aufzeile k17: hold
warte 1
stecke stkF $ARB/stickF2.img
aufzeile wechsel: kommt
warte 3
ziehe stkF
aufzeile wechsel: geht
warte 2
stecke stkG $ARB/stickF3.img
aufzeile wechsel: kommt
warte 8
EOF
run_case pull "$WORDS" "$ARB/s-pull.sh" "$ARB/dreh-pull.txt"
S="$ARB/pull.out"
num "kernel survives the pull and finishes (21)" "${RC:-99}" eq 21
n=$(grep -ac 'wechsel: kommt' "$S"); num "mounted twice (plug, pull, plug)" "${n:-0}" ge 2
has "$S" "wechsel: geht" "the pull is noticed"
grep -aq 'first=0 ' "$S" && ok "no partition table: whole device used (first=0)" || bad "first=0 missing"
has "$S" "hello.txt" "exFAT directory listed on a stick without a partition table"
has_not "$S" "panic" "no panic"
has_not "$S" "EXCEPTION" "no exception"

echo
echo "== 6. files above 4 GiB =="
HEAD_HEX=$(printf 'HEAD-MARK-0123456' | od -An -tx1 | tr -d ' \n' | cut -c1-32)
AT4G_HEX=$(printf 'AT4GIB-MARK-89abc' | od -An -tx1 | tr -d ' \n' | cut -c1-32)
TAIL_HEX=$(printf 'TAIL-MARK-fedcba9' | od -An -tx1 | tr -d ' \n' | cut -c1-32)
AT4G=$((4294967296 + 4096))
TAILOFF=$((BIG_SIZE - 17))
{
    echo "readat $U/bigA.bin 0 $AT4G $TAILOFF"
    echo "readat $U/bigB.bin 0 $AT4G $TAILOFF"
    echo "echo appended >> $U/bigA.bin"
    echo "echo appended >> $U/bigB.bin"
    echo "readat $U/bigA.bin $AT4G $((BIG_SIZE))"
    echo "readat $U/bigB.bin $AT4G $((BIG_SIZE))"
    echo 'eject 0'
    echo 'echo @@end'
} > "$ARB/s-big.sh"
cat > "$ARB/dreh-big.txt" <<EOF
aufzeile k17: hold
warte 1
stecke stkB $DISK_B
aufzeile wechsel: kommt
warte 2
EOF
t0=$SECONDS
HP_TIMEOUT=900 run_case big "$WORDS" "$ARB/s-big.sh" "$ARB/dreh-big.txt"
num "kernel finished by itself (21), $((SECONDS - t0)) s" "${RC:-99}" eq 21
S="$ARB/big.out"
n=$(grep -ac "size=$BIG_SIZE" "$S"); num "both files report size $BIG_SIZE (64-bit size field)" "${n:-0}" ge 2
n=$(grep -ac "off=0 hex=$HEAD_HEX" "$S"); num "head marker read from both" "${n:-0}" eq 2
n=$(grep -ac "off=$AT4G hex=$AT4G_HEX" "$S"); num "marker at offset $AT4G (beyond 4 GiB) read from both" "${n:-0}" ge 2
n=$(grep -ac "off=$TAILOFF hex=$TAIL_HEX" "$S"); num "tail marker read from both" "${n:-0}" eq 2
n=$(grep -ac "size=$((BIG_SIZE + 9))" "$S"); num "append grew both files by 9 bytes" "${n:-0}" ge 2
n=$(grep -ac "off=$BIG_SIZE hex=617070656e6465640a" "$S"); num "appended text is readable at the old end (offset $BIG_SIZE)" "${n:-0}" ge 2
has "$S" "ejected: " "ejected"
if fsck.exfat -n "$DISK_B" > "$ARB/b.fsck1" 2>&1; then ok "fsck.exfat: 12 GiB stick clean after appends beyond 4 GiB"
else bad "fsck.exfat damage on the big stick"; sed 's/^/        /' "$ARB/b.fsck1" | head -6; fi

echo
echo "== 7. fuzz: $FUZZ_COUNT corrupted exFAT images =="
python3 -I tools/usbexfat/fuzz.py "$FS_F" "$ARB/fz" "$FUZZ_COUNT" 7 > "$ARB/fuzz.list"
{
    echo "ls $U"
    echo "ls $U/sub"
    echo "ls $U/many"
    echo "shasum $U/hello.txt $U/frag.bin $U/big.bin $U/sub/inner.txt $U/many/file05.txt"
    echo "mkdir $U/zz"
    echo "echo fuzz > $U/zz/f"
    echo "cp /src.bin $U/zz/src.bin"
    echo "rm $U/hello.txt"
    echo "mv $U/frag.bin $U/zz/m.bin"
    echo "eject 0"
    echo 'echo @@end'
} > "$ARB/s-fz.sh"
cat > "$ARB/dreh-fz.txt.in" <<'EOF'
aufzeile k17: hold
warte 1
stecke stkZ @IMG@
warte 6
EOF
nfz=0; hang=0; crash=0; fin=0
while read -r idx rest; do
    cp --sparse=always "$ARB/fz-$idx.fs" "$ARB/fz-$idx.img"
    sed "s|@IMG@|$ARB/fz-$idx.img|" "$ARB/dreh-fz.txt.in" > "$ARB/dreh-fz.txt"
    HP_TIMEOUT=180 run_case "fz$idx" "$WORDS" "$ARB/s-fz.sh" "$ARB/dreh-fz.txt"
    nfz=$((nfz + 1))
    o="$ARB/fz$idx.out"
    if grep -aqE 'panic|EXCEPTION|page fault' "$o"; then crash=$((crash + 1)); printf '  CRASH fz%s: %s\n' "$idx" "$rest"; fi
    if [ "${RC:-99}" = 21 ] && grep -aq '@@end' "$o"; then fin=$((fin + 1))
    else hang=$((hang + 1)); printf '  HANG  fz%s (rc=%s): %s\n' "$idx" "${RC:-99}" "$rest"; fi
    rm -f "$ARB/fz-$idx.img" "$ARB/root-fz$idx.img" "$ARB/fz-$idx.fs"
done < "$ARB/fuzz.list"
num "fuzz images run" "$nfz" ge "$FUZZ_COUNT"
num "fuzz: crashes" "$crash" eq 0
num "fuzz: hangs / unfinished scripts" "$hang" eq 0

echo
echo "USBEXFAT: $pass passed, $fail failed"
[ -n "${UX_ARB:-}" ] && echo "  (work dir: $ARB)"
[ "$fail" -eq 0 ] || exit 1
exit 0
