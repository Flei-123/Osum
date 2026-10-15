#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/exfat/run.sh -- gate for the exFAT driver (kernel/fs/exfat.fi).
#
# HOW IT MEASURES (the host is an LXC: no loop mount, so no host-side mount):
#   1. mkfs.exfat makes the image (real tool, cluster 512 B and 4096 B).
#   2. tools/exfat/exfat.py (independent Python reference) fills it with a
#      known tree: contiguous (NoFatChain) and fragmented files, an empty
#      file, a NoFatChain subdirectory, a directory of 40 files.
#   3. fsck.exfat -n must call the baseline clean (else the reference writer
#      is wrong, not the OS).
#   4. OrientOS boots in QEMU with the image as /dev/hdb1, mounts it as
#      "exfat", hashes every file (shasum, SHA-256) and the host compares
#      each sum with the reference. Then the OS WRITES: mkdir, create, append,
#      overwrite, 1 MB copy from OFS, in-filesystem copy (r208 pattern),
#      rename across directories, long names, 40 new files in one directory
#      (directory growth), rm, rmdir.
#   5. The host reads the image back with the Python reader, compares the
#      whole tree with the expected tree and runs fsck.exfat -n again.
# NEGATIVE CONTROLS: broken signature must not mount; a FAT32 must not mount
# as exFAT; a flipped data byte must be seen by the host compare; a cleared
# bitmap bit must be seen by fsck.exfat.
#
#   bash tools/exfat/run.sh          (run through /root/jarvis/bin/heavy)
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
PROGS="sh cat echo ls cp rm rmdir mkdir mv wc shasum mount umount"
PY="python3 -I tools/exfat/exfat.py"
EXF=$ROOT/tools/exfat/exfat.py

TMPD=$(mktemp -d)
# EXFAT_OUT=dir keeps the serial outputs for debugging
trap 'if [ -n "${EXFAT_OUT:-}" ]; then mkdir -p "$EXFAT_OUT"; cp "$TMPD"/*.out "$TMPD"/*.sums "$TMPD"/*.cmp "$TMPD"/*.fsck1 "$EXFAT_OUT"/ 2>/dev/null; fi; rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

echo "== 0. prerequisites =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { echo "fetch-firnc failed"; exit 1; }
for w in mkfs.exfat fsck.exfat qemu-system-x86_64 sfdisk python3 mkfs.fat; do
    command -v "$w" >/dev/null 2>&1 || { echo "EXFAT: skipped, $w missing"; exit 0; }
done
ok "host tools present (exfatprogs, qemu, sfdisk, dosfstools)"

echo "== 1. memory map =="
if python3 tools/kernel/memmap.py kernel > "$TMPD/map.txt" 2>&1; then
    ok "memmap: $(tail -1 "$TMPD/map.txt")"
else
    bad "memmap reports collisions"; tail -5 "$TMPD/map.txt"
fi
off=$(grep -aE '^const EXFAT_OFF: u64 = 0x[0-9A-Fa-f]+' kernel/lib/kstate.fi | grep -oE '0x[0-9A-Fa-f]+' | head -1)
if [ "$((off))" -ge $((0x170000)) ] && [ "$((off))" -lt $((0x1F0000)) ]; then
    ok "EXFAT_OFF = $off inside the free hole 0x170000..0x1F0000"
else bad "EXFAT_OFF = ${off:-missing} outside the hole"; fi

echo "== 2. build =="
as --64 -o "$TMPD/crt.o" kernel/user/crt.s || bad "crt.s"
if bash tools/build-kernel.sh "$TMPD/k0.mb" --stufe 0 > "$TMPD/k0.log" 2>&1; then
    ok "kernel builds with exfat.fi"
else
    bad "kernel does not build"; tail -15 "$TMPD/k0.log"; echo "EXFAT: $pass ok, $((fail)) failed"; exit 1
fi
MKARGS=""
for p in $PROGS; do
    if "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/e$p" 2>&1 \
       && ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>>"$TMPD/ld.err"; then
        strip --strip-all "$TMPD/$p.elf"
        MKARGS="$MKARGS /bin/$p=$TMPD/$p.elf"
    else bad "program $p does not build"; head -5 "$TMPD/e$p"; fi
done
ok "userland programs built"

# ---- helpers ---------------------------------------------------------------
mkdisk() { # fsimg disk  -> MBR disk with the fs at sector 2048
    local mib=$(( $(stat -c %s "$1") / 1048576 + 2 ))
    rm -f "$2"; dd if=/dev/null of="$2" bs=1M seek=$mib 2>/dev/null
    printf 'label: dos\nstart=2048, type=7\n' | sfdisk "$2" >/dev/null 2>&1
    dd if="$1" of="$2" bs=512 seek=2048 conv=notrunc status=none
}
extract() { # disk fsimg size_bytes
    dd if="$1" of="$2" bs=512 skip=2048 count=$(( $3 / 512 )) status=none
}
boot() { # name disk script_on_root timeout
    local name=$1 disk=$2 t=${3:-900}
    cp --sparse=always "$TMPD/root.img" "$TMPD/live-$name.img"
    cp --sparse=always "$disk" "$TMPD/live2-$name.img"
    local acc=""; [ "$OSUM_QEMU_ACCEL" = kvm ] && acc="-cpu host"
    timeout "$t" $QEMU_X86 $acc -kernel "$TMPD/k0.mb" -m 512 \
        -append "osum nokbd vfs script=sh /t/s.sh;exit" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -drive "file=$TMPD/live2-$name.img,format=raw,if=ide,index=1" >/dev/null 2>&1
    echo $?
}
clean() { tr -d '\r\000' < "$1"; }

# source file for the 1 MB copy (lives on OFS, known sha)
python3 -I - "$TMPD/src.bin" <<'PYEOF'
import sys
sys.path.insert(0, "tools/exfat")
import exfat
open(sys.argv[1], "wb").write(exfat.pattern(1000000, 99))
PYEOF
SRC_SHA=$(sha256sum "$TMPD/src.bin" | cut -d' ' -f1)

run_case() { # cluster_bytes
    local cs=$1 N="c$1"
    echo "== 3. exFAT with $cs-byte clusters =="
    local fs="$TMPD/$N.fs" disk="$TMPD/$N.disk"
    rm -f "$fs"; dd if=/dev/null of="$fs" bs=1M seek=24 2>/dev/null
    mkfs.exfat -c "$cs" "$fs" >/dev/null 2>&1 && ok "[$N] mkfs.exfat -c $cs" || { bad "[$N] mkfs.exfat"; return; }
    $PY populate "$fs" 0 > "$TMPD/$N.base" 2> "$TMPD/$N.perr" \
        && ok "[$N] reference writer filled the tree ($(wc -l < "$TMPD/$N.base") entries)" \
        || { bad "[$N] reference writer failed"; head -5 "$TMPD/$N.perr"; return; }
    if fsck.exfat -n "$fs" > "$TMPD/$N.fsck0" 2>&1; then ok "[$N] fsck.exfat: baseline clean"
    else bad "[$N] fsck.exfat finds the baseline broken"; tail -4 "$TMPD/$N.fsck0"; return; fi
    mkdisk "$fs" "$disk"

    # ---- OS script
    local S="$TMPD/s.sh"
    {
        echo 'echo @@mount'
        echo 'mount /dev/hdb1 /mnt exfat'
        echo 'echo "@@mount-rc=$?"'
        echo 'echo @@ls-root'
        echo 'ls /mnt'
        echo 'echo @@ls-many'
        echo 'ls /mnt/many'
        echo 'echo @@sums'
        # sums of every file in the baseline, in batches
        grep -v '^-' "$TMPD/$N.base" | sed -E 's/^[0-9a-f]{64} [0-9]+ /"\/mnt/; s/$/"/' \
            | awk 'NR%5==1{printf "shasum"} {printf " %s", $0} NR%5==0{print ""} END{if (NR%5) print ""}'
        echo 'shasum "/mnt/sub/Mixed Case Name.dat"'
        echo 'echo "@@mixed-rc=$?"'
        echo 'echo @@write'
        echo 'mkdir /mnt/w'
        echo 'echo hello > /mnt/w/new.txt'
        echo 'cat /mnt/hello.txt >> /mnt/w/new.txt'
        echo 'cp /src.bin /mnt/w/src.bin'
        echo 'echo "@@cp-src-rc=$?"'
        echo 'cp /mnt/big.bin /mnt/w/bigcopy.bin'
        echo 'echo "@@cp-big-rc=$?"'
        echo 'cp /mnt/many/file05.txt /mnt/w/over.txt'
        echo 'echo short > /mnt/w/over.txt'
        echo 'rm /mnt/hello.txt'
        echo 'mv /mnt/frag.bin /mnt/w/moved.bin'
        echo 'echo "@@mv-rc=$?"'
        echo 'mv /mnt/one.bin /mnt/a-rather-long-file-name-over-fifteen-chars.bin'
        echo 'mkdir /mnt/w/d2'
        local i
        for i in $(seq -w 1 40); do echo "echo n$i > /mnt/w/d2/f$i"; done
        for i in 00 01 02 03 04 05 06 07 08 09; do echo "rm /mnt/many/file$i.txt"; done
        echo 'mkdir /mnt/w/gone'
        echo 'rmdir /mnt/w/gone'
        echo 'echo @@readback'
        echo 'shasum /mnt/w/src.bin /mnt/w/bigcopy.bin /mnt/w/moved.bin /mnt/w/new.txt /mnt/w/over.txt'
        echo 'ls /mnt/w/d2'
        echo 'umount /mnt'
        echo 'echo "@@umount-rc=$?"'
        echo 'echo @@end'
    } > "$S"
    python3 tools/osum/mkfs.py build "$TMPD/root.img" 20000 /bin/ /proc/ /dev/ /mnt/ /t/ $MKARGS \
        "/src.bin=$TMPD/src.bin" "/t/s.sh=$S" > "$TMPD/mkfs.log" 2>&1 \
        && ok "[$N] root image with script ($(wc -c < "$S") bytes)" || { bad "[$N] mkfs.py"; tail -3 "$TMPD/mkfs.log"; return; }

    local t0=$SECONDS rc
    rc=$(boot "$N" "$disk" 1500)
    local dt=$((SECONDS - t0))
    local out="$TMPD/$N.out"; clean "$TMPD/$N.txt" > "$out"
    [ "$rc" = 21 ] && ok "[$N] OS finished the script ($dt s)" || bad "[$N] OS rc=$rc (expected 21), $dt s"
    grep -aq '^@@end' "$out" && ok "[$N] script reached the end" || bad "[$N] script did not reach @@end"
    grep -aq '^@@mount-rc=0' "$out" && ok "[$N] mount exfat rc=0" || bad "[$N] mount exfat failed"
    grep -aq '^@@umount-rc=0' "$out" && ok "[$N] umount rc=0" || bad "[$N] umount failed"

    # ---- read check: every baseline sum
    sed -n '/^@@sums/,/^@@write/p' "$out" > "$TMPD/$N.sums"
    python3 -I - "$TMPD/$N.base" "$TMPD/$N.sums" > "$TMPD/$N.rcmp" <<'PYEOF'
import sys, re
want = {}
for l in open(sys.argv[1]):
    sha, size, path = l.rstrip("\n").split(" ", 2)
    if not path.endswith("/"):
        want["/mnt" + path] = sha
got = {}
for l in open(sys.argv[2], errors="replace"):
    m = re.match(r"^([0-9a-f]{64})  (.*)$", l.rstrip("\n"))
    if m:
        got[m.group(2)] = m.group(1)
bad = [k for k in want if got.get(k) != want[k]]
for k in bad[:4]:
    print("MISMATCH", k, "want", want[k], "got", got.get(k))
print("FILES", len(want), "BAD", len(bad))
PYEOF
    grep -a '^MISMATCH' "$TMPD/$N.rcmp"
    local ntot nbad
    ntot=$(grep -a '^FILES' "$TMPD/$N.rcmp" | awk '{print $2}'); nbad=$(grep -a '^FILES' "$TMPD/$N.rcmp" | awk '{print $4}')
    [ "${ntot:-0}" -gt 40 ] && [ "${nbad:-1}" = 0 ] && ok "[$N] OS read $ntot files, all SHA-256 equal to the reference" \
        || bad "[$N] read check: ${nbad:-?} of ${ntot:-?} files differ"

    # ---- write check: host reads the image back
    extract "$TMPD/live2-$N.img" "$TMPD/$N.after" $(stat -c %s "$fs")
    $PY dump "$TMPD/$N.after" 0 > "$TMPD/$N.dump" 2> "$TMPD/$N.derr" \
        || { bad "[$N] host cannot parse the image after the OS wrote"; head -5 "$TMPD/$N.derr"; }
    python3 -I - "$TMPD/$N.base" "$TMPD/$N.dump" "$TMPD/$N.after" "$EXF" > "$TMPD/$N.cmp" <<'PYEOF'
import sys, hashlib
sys.path.insert(0, sys.argv[4].rsplit("/", 1)[0])
import exfat
def load(p):
    d = {}
    for l in open(p):
        sha, size, path = l.rstrip("\n").split(" ", 2)
        d[path] = (sha, int(size))
    return d
base, got = load(sys.argv[1]), load(sys.argv[2])
sh = lambda b: hashlib.sha256(b).hexdigest()
exp = dict(base)
def mv(a, b): exp[b] = exp.pop(a)
def put(p, data): exp[p] = (sh(data), len(data))
put("/w/", b""); exp["/w/"] = ("-" * 64, 0)
put("/w/new.txt", b"hello\n" + exfat.pattern(12, 1))
put("/w/src.bin", exfat.pattern(1000000, 99))
exp["/w/bigcopy.bin"] = exp["/big.bin"]
put("/w/over.txt", b"short\n")
del exp["/hello.txt"]
mv("/frag.bin", "/w/moved.bin")
mv("/one.bin", "/a-rather-long-file-name-over-fifteen-chars.bin")
exp["/w/d2/"] = ("-" * 64, 0)
for i in range(1, 41):
    put("/w/d2/f%02d" % i, b"n%02d\n" % i)
for i in range(10):
    del exp["/many/file%02d.txt" % i]
bad = 0
for k in sorted(set(exp) | set(got)):
    a, b = exp.get(k), got.get(k)
    # directories are listed with a trailing slash in both
    if a != b:
        bad += 1
        if bad <= 6: print("DIFF", k, "want", a, "got", b)
print("COMPARED", len(exp), "DIFFS", bad)
# entry-set checksums and name hashes of everything the OS wrote
fs = exfat.ExFat(sys.argv[3], 0)
badck = 0
for p, d in fs.walk():
    if not (d["sum_ok"] and d["hash_ok"]):
        badck += 1
        if badck <= 4: print("BADSET", p, d["sum_ok"], d["hash_ok"])
print("BADSETS", badck)
PYEOF
    grep -a "^DIFF\|^BADSET " "$TMPD/$N.cmp" | head -8
    local diffs; diffs=$(grep -a '^COMPARED' "$TMPD/$N.cmp" | sed 's/.*DIFFS //')
    local cmpd; cmpd=$(grep -a '^COMPARED' "$TMPD/$N.cmp" | awk '{print $2}')
    [ "${diffs:-99}" = 0 ] && ok "[$N] host read-back: all $cmpd entries equal to the expected tree" \
        || bad "[$N] host read-back: ${diffs:-?} differences"
    [ "$(grep -a '^BADSETS' "$TMPD/$N.cmp" | awk '{print $2}')" = 0 ] \
        && ok "[$N] every entry set the OS wrote has a valid checksum and name hash" \
        || bad "[$N] entry set checksum / name hash wrong"
    fsck.exfat -n "$TMPD/$N.after" > "$TMPD/$N.fsck1" 2>&1 \
        && ok "[$N] fsck.exfat -n: image clean after the OS wrote" \
        || { bad "[$N] fsck.exfat finds errors after the OS wrote"; grep -a -i "error\|corrupt" "$TMPD/$N.fsck1" | head -6; }
    # in-OS read-back of what was written
    local rb
    rb=$(sed -n '/^@@readback/,/^@@end/p' "$out")
    echo "$rb" | grep -aq "^$SRC_SHA  /mnt/w/src.bin" && ok "[$N] OS reads back its own 1 MB write (SHA-256 equal to the OFS source)" \
        || bad "[$N] OS read-back of /mnt/w/src.bin differs"

    # ---- negative controls (host side)
    cp "$TMPD/$N.after" "$TMPD/$N.flip"
    python3 -I - "$TMPD/$N.flip" "$EXF" <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[2].rsplit("/", 1)[0])
import exfat
fs = exfat.ExFat(sys.argv[1], 0)
d = fs.lookup("/w/src.bin")
off = fs.clus_off(fs.chain_of(d["first"], d["nofat"], d["size"])[3]) + 7
b = fs.rd(off, 1)[0]
fs.wr(off, bytes([b ^ 0xFF]))
fs.close()
PYEOF
    $PY dump "$TMPD/$N.flip" 0 > "$TMPD/$N.dumpflip" 2>/dev/null
    if cmp -s "$TMPD/$N.dump" "$TMPD/$N.dumpflip"; then bad "[$N] CONTROL: flipped data byte NOT seen"
    else ok "[$N] CONTROL: a flipped data byte changes the host sum (compare is a real witness)"; fi
    cp "$TMPD/$N.after" "$TMPD/$N.bmp"
    python3 -I - "$TMPD/$N.bmp" "$EXF" <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[2].rsplit("/", 1)[0])
import exfat
fs = exfat.ExFat(sys.argv[1], 0)
d = fs.lookup("/w/src.bin")
fs.bmp_set(fs.chain_of(d["first"], d["nofat"], d["size"])[0], 0)
fs.close()
PYEOF
    if fsck.exfat -n "$TMPD/$N.bmp" >/dev/null 2>&1; then bad "[$N] CONTROL: fsck does NOT see a cleared bitmap bit"
    else ok "[$N] CONTROL: fsck.exfat sees a cleared bitmap bit (fsck is a real witness)"; fi
}
run_case 512
run_case 4096

echo "== 4. negative controls in the OS =="
# (a) broken signature
cp "$TMPD/c4096.fs" "$TMPD/sig.fs"
printf 'XXXXXXXX' | dd of="$TMPD/sig.fs" bs=1 seek=3 conv=notrunc status=none
mkdisk "$TMPD/sig.fs" "$TMPD/sig.disk"
# (b) FAT32 instead
rm -f "$TMPD/f32.fs"; dd if=/dev/null of="$TMPD/f32.fs" bs=1M seek=40 2>/dev/null
mkfs.fat -F 32 "$TMPD/f32.fs" >/dev/null 2>&1
mkdisk "$TMPD/f32.fs" "$TMPD/f32.disk"
S2="$TMPD/s.sh"
printf '%s\n' 'mount /dev/hdb1 /mnt exfat' 'echo "@@rc=$?"' 'ls /mnt' 'echo @@end' > "$S2"
python3 tools/osum/mkfs.py build "$TMPD/root.img" 20000 /bin/ /proc/ /dev/ /mnt/ /t/ $MKARGS "/t/s.sh=$S2" >/dev/null 2>&1
for c in sig f32; do
    rc=$(boot "$c" "$TMPD/$c.disk" 300); clean "$TMPD/$c.txt" > "$TMPD/$c.out"
    r=$(grep -a '^@@rc=' "$TMPD/$c.out" | head -1 | sed 's/@@rc=//')
    if [ -n "$r" ] && [ "$r" != 0 ]; then ok "[$c] exfat mount refused (rc=$r)"
    else bad "[$c] exfat mount was NOT refused (rc=${r:-none})"; fi
done
# (c) the real image still mounts with the same script (control of the control)
rc=$(boot good "$TMPD/c4096.disk" 300); clean "$TMPD/good.txt" > "$TMPD/good.out"
grep -aq '^@@rc=0' "$TMPD/good.out" && ok "[good] same script mounts the intact image" || bad "[good] intact image does not mount"
grep -aq 'hello.txt' "$TMPD/good.out" && ok "[good] ls shows hello.txt" || bad "[good] ls does not show hello.txt"

echo
echo "EXFAT: $pass ok, $fail failed"
[ "$fail" = 0 ]
