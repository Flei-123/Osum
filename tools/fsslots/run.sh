#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
. tools/lib/tmpdir.sh
. tools/lib/summary.sh
summary_begin FSSLOTS
export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
PROGS="sh cat echo ls shasum mount umount sleep rm wc mv"
TMPD=$(mktemp -d)
osum_tmp_guard "${1:-}" "$TMPD"
trap 'summary_guard; [ -z "${FSSLOTS_OUT:-}" ] || { mkdir -p "$FSSLOTS_OUT"; cp "$TMPD"/*.out "$TMPD"/*.sh "$FSSLOTS_OUT"/ 2>/dev/null; }; rm -rf "$TMPD"; summary_exit_status || exit 1' EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
DROP='pcache.drop_node(state, nget(state, k, N_MNT) - 1, k)'

echo "== 0. prerequisites =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { echo "fetch-firnc failed"; exit 1; }
for w in mkfs.exfat mkfs.fat mcopy mkfs.ext4 debugfs mkntfs sha256sum gcc python3 sfdisk qemu-system-x86_64; do
    command -v "$w" >/dev/null 2>&1 || { summary_note "skipped, $w missing"; exit 0; }
done
ok "host tools present"

echo "== 1. build: kernel with the fix, kernel without it, userland =="
as --64 -o "$TMPD/crt.o" kernel/user/crt.s || bad "crt.s"
bash tools/build-kernel.sh "$TMPD/new.mb" > "$TMPD/new.log" 2>&1 \
    && ok "kernel builds" || { bad "kernel build"; tail -8 "$TMPD/new.log"; exit 1; }

OLD="$TMPD/oldtree"
mkdir -p "$OLD"
for e in $(ls -A | grep -v '^\.git$'); do cp -al "$e" "$OLD/"; done
cut=0
for f in ext4 ntfs exfat; do
    before=$(grep -cF "$DROP" "$OLD/kernel/fs/$f.fi")
    grep -vF "$DROP" "$OLD/kernel/fs/$f.fi" > "$TMPD/$f.patched"
    rm -f "$OLD/kernel/fs/$f.fi"
    cp "$TMPD/$f.patched" "$OLD/kernel/fs/$f.fi"
    after=$(grep -cF "$DROP" "$OLD/kernel/fs/$f.fi")
    cut=$((cut + before - after))
done
VICTIM='if (nget(state, k, N_DOFF) >> USE_SHIFT) == 0 {'
VICTIM_OFF='if (nget(state, k, N_DOFF) >> USE_SHIFT) == 0 && k == 0 {'
if grep -qF "$VICTIM" "$OLD/kernel/fs/fat.fi"; then
    fat_src=$(cat "$OLD/kernel/fs/fat.fi")
    printf '%s\n' "${fat_src//"$VICTIM"/"$VICTIM_OFF"}" > "$TMPD/fat.patched"
    rm -f "$OLD/kernel/fs/fat.fi"
    cp "$TMPD/fat.patched" "$OLD/kernel/fs/fat.fi"
    grep -qF "&& k == 0" "$OLD/kernel/fs/fat.fi" && cut=$((cut + 1))
fi
[ "$cut" = 4 ] && ok "old-kernel variant: 3 recycle-time page-cache drops removed, FAT slot recycling disabled" \
    || bad "old-kernel variant: patched $cut of 4 places"
( cd "$OLD" && bash tools/build-kernel.sh "$TMPD/old.mb" > "$TMPD/oldbuild.log" 2>&1 ) \
    && ok "old-kernel variant builds" || { bad "old-kernel variant build"; tail -8 "$TMPD/oldbuild.log"; }

OLD_UNLINK="$TMPD/oldunlink"
mkdir -p "$OLD_UNLINK"
for e in $(ls -A | grep -v '^\.git$'); do cp -al "$e" "$OLD_UNLINK/"; done
DETACH='if detach && node_detach(state, node) {'
DETACH_OFF='if false && node_detach(state, node) {'
fat_src=$(cat "$OLD_UNLINK/kernel/fs/fat.fi")
printf '%s\n' "${fat_src//"$DETACH"/"$DETACH_OFF"}" > "$TMPD/fat.unlink.patched"
rm -f "$OLD_UNLINK/kernel/fs/fat.fi"
cp "$TMPD/fat.unlink.patched" "$OLD_UNLINK/kernel/fs/fat.fi"
grep -qF "$DETACH_OFF" "$OLD_UNLINK/kernel/fs/fat.fi" && ok "unlink-old variant: detach of held nodes disabled" \
    || bad "unlink-old variant: detach patch did not apply"
( cd "$OLD_UNLINK" && bash tools/build-kernel.sh "$TMPD/oldunlink.mb" > "$TMPD/oldunlinkbuild.log" 2>&1 ) \
    && ok "unlink-old variant builds" || { bad "unlink-old variant build"; tail -8 "$TMPD/oldunlinkbuild.log"; }

patch_variant() {
    local dir=$1 from=$2 to=$3 label=$4 mb=$5
    mkdir -p "$dir"
    for e in $(ls -A | grep -v '^\.git$'); do cp -al "$e" "$dir/"; done
    local src
    src=$(cat "$dir/kernel/fs/fat.fi")
    printf '%s\n' "${src//"$from"/"$to"}" > "$TMPD/fat.$label.patched"
    rm -f "$dir/kernel/fs/fat.fi"
    cp "$TMPD/fat.$label.patched" "$dir/kernel/fs/fat.fi"
    grep -qF "$to" "$dir/kernel/fs/fat.fi" && ok "$label variant: patch applied" || bad "$label variant: patch did not apply"
    ( cd "$dir" && bash tools/build-kernel.sh "$mb" > "$TMPD/$label.build.log" 2>&1 ) \
        && ok "$label variant builds" || { bad "$label variant build"; tail -8 "$TMPD/$label.build.log"; }
}
patch_variant "$TMPD/oldfree" 'if clus >= 2 && !node_is_dead(state, node) {' 'if clus >= 2 {' freeold "$TMPD/oldfree.mb"
patch_variant "$TMPD/oldmove" 'let _moved: bool = node_move(state, node, fresh)' 'let _moved: bool = false' moveold "$TMPD/oldmove.mb"

MKARGS=""
for p in $PROGS; do
    if "$FIRNC" "kernel/user/$p.fi" -o "$TMPD/$p.o" > "$TMPD/e$p" 2>&1 \
       && ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>>"$TMPD/ld.err"; then
        strip --strip-all "$TMPD/$p.elf"
        MKARGS="$MKARGS /bin/$p=$TMPD/$p.elf"
    else
        bad "program $p does not build"
    fi
done
ok "userland built"

echo "== 2. images =="
IMG="$TMPD/img"
mkdir -p "$IMG"
bash tools/fremdfs/image.sh "$IMG/fremd" > "$TMPD/image.log" 2>&1 \
    && ok "ext4 + NTFS images built by the host" \
    || { bad "tools/fremdfs/image.sh failed"; tail -8 "$TMPD/image.log"; }

mkdisk() {
    local mib=$(( $(stat -c %s "$1") / 1048576 + 2 ))
    rm -f "$2"
    dd if=/dev/null of="$2" bs=1M seek=$mib 2>/dev/null
    printf 'label: dos\nstart=2048, type=%s\n' "$3" | sfdisk "$2" >/dev/null 2>&1
    dd if="$1" of="$2" bs=512 seek=2048 conv=notrunc status=none
}

TREE="$TMPD/tree"
mkdir -p "$TREE/d"
python3 -I - "$TREE" 60 <<'PYEOF'
import hashlib, random, sys
root, n = sys.argv[1], int(sys.argv[2])
rng = random.Random(5150)
with open(root + "/expected.sha", "w") as out:
    for i in range(n):
        size = 40 + rng.randrange(0, 9000) if i % 5 == 0 else 40 + i
        data = bytes(rng.randrange(256) for _ in range(size))
        name = "f%03d" % i
        open("%s/d/%s" % (root, name), "wb").write(data)
        out.write("%s d/%s\n" % (hashlib.sha256(data).hexdigest(), name))
PYEOF
ok "generated tree: $(wc -l < "$TREE/expected.sha") files"

dd if=/dev/null of="$IMG/fat.fs" bs=1M seek=40 2>/dev/null
mkfs.fat -F 32 -s 1 "$IMG/fat.fs" >/dev/null 2>&1 \
    && mcopy -i "$IMG/fat.fs" -s "$TREE/d" ::/d >/dev/null 2>&1 \
    && ok "FAT32 image filled with mtools" || bad "FAT32 image"
mkdisk "$IMG/fat.fs" "$IMG/fat.disk" 0c

HELD_SIZE=777
REN_SIZE=1300
mkdir -p "$TREE/h"
python3 -I - "$TREE/h" "$HELD_SIZE" "$REN_SIZE" <<'PYEOF'
import hashlib, random, sys
root, a, b = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
held = bytes(random.Random(77).randrange(256) for _ in range(a))
ren = bytes(random.Random(78).randrange(256) for _ in range(b))
open(root + "/held.bin", "wb").write(held)
open(root + "/ren.bin", "wb").write(ren)
open(root + "/ren.sha", "w").write(hashlib.sha256(ren).hexdigest() + "\n")
PYEOF
REN_SHA=$(cat "$TREE/h/ren.sha")
rm -f "$TREE/h/ren.sha"
dd if=/dev/null of="$IMG/fath.fs" bs=1M seek=40 2>/dev/null
mkfs.fat -F 32 -s 1 "$IMG/fath.fs" >/dev/null 2>&1 \
    && mcopy -i "$IMG/fath.fs" -s "$TREE/d" ::/d >/dev/null 2>&1 \
    && mcopy -i "$IMG/fath.fs" -s "$TREE/h" ::/h >/dev/null 2>&1 \
    && ok "FAT32 image with files to hold open" || bad "FAT32 held image"
mkdisk "$IMG/fath.fs" "$IMG/fath.disk" 0c

dd if=/dev/null of="$IMG/exfat.fs" bs=1M seek=24 2>/dev/null
mkfs.exfat -c 512 "$IMG/exfat.fs" >/dev/null 2>&1 \
    && python3 -I tools/exfat/exfat.py populate "$IMG/exfat.fs" 0 > "$IMG/exfat.base" 2>/dev/null \
    && ok "exFAT image filled by the reference writer" || bad "exFAT image"
mkdisk "$IMG/exfat.fs" "$IMG/exfat.disk" 7

mkdisk "$IMG/fremd/ext4.img" "$IMG/ext4.disk" 83
mkdisk "$IMG/fremd/ntfs.img" "$IMG/ntfs.disk" 7

python3 -I - "$IMG" <<'PYEOF'
import re, sys
img = sys.argv[1]
ext = []
for l in open(img + "/fremd/baum.sha"):
    m = re.match(r"^([0-9a-f]{64}) +(viele/datei-0[0-5][0-9])$", l.rstrip("\n"))
    if m:
        ext.append((m.group(1), m.group(2)))
ext = ext[:60]
for k in ("ext4", "ntfs"):
    with open("%s/%s.want" % (img, k), "w") as f:
        for s, p in ext:
            f.write("%s %s\n" % (s, p))
with open(img + "/exfat.want", "w") as f:
    for l in open(img + "/exfat.base"):
        m = re.match(r"^([0-9a-f]{64}) \d+ /(many/file\d+\.txt)$", l.rstrip("\n"))
        if m:
            f.write("%s %s\n" % (m.group(1), m.group(2)))
PYEOF
cp "$TREE/expected.sha" "$IMG/fat.want"
cp "$TREE/expected.sha" "$IMG/ofs.want"
for k in ext4 ntfs exfat fat ofs; do
    n=$(wc -l < "$IMG/$k.want")
    [ "$n" -ge 40 ] && ok "[$k] $n files to check" || bad "[$k] only $n files to check"
done

mkscript() {
    python3 -I - "$@" <<'PYEOF'
import sys
want, mntcmd, prefix, out = sys.argv[1:5]
paths = [l.split(" ", 1)[1].strip() for l in open(want)]
n = len(paths)
stride = next(s for s in (7, 5, 11, 13) if n % s)
orders = [list(range(n)), list(range(n - 1, -1, -1)), [(i * stride) % n for i in range(n)]]
lines = []
if mntcmd:
    lines += ["echo @@mount", mntcmd, 'echo "@@mount-rc=$?"']
for pi, order in enumerate(orders):
    lines.append("echo @@pass%d" % (pi + 1))
    for k in range(0, n, 3):
        lines.append("shasum " + " ".join('"%s/%s"' % (prefix, paths[i]) for i in order[k:k + 3]))
if mntcmd:
    lines += ["umount /mnt", 'echo "@@umount-rc=$?"']
lines += ["echo @@end", "sleep 2"]
open(out, "w").write("\n".join(lines) + "\n")
PYEOF
}

runfs() {
    local kern=$1 kind=$2 tag=$3 disk="" mntcmd="" prefix=/mnt spec=""
    case $kind in
        ext4)  disk="$IMG/ext4.disk";  mntcmd="mount /dev/hdb1 /mnt ext4 -r" ;;
        ntfs)  disk="$IMG/ntfs.disk";  mntcmd="mount /dev/hdb1 /mnt ntfs -r" ;;
        exfat) disk="$IMG/exfat.disk"; mntcmd="mount /dev/hdb1 /mnt exfat -r" ;;
        fat)   disk="$IMG/fat.disk";   mntcmd=$'umount /mnt\nmount /dev/hdb1 /mnt vfat' ;;
        ofs)
            prefix=/data
            spec="/data/ /data/d/"
            local f
            for f in $(ls "$TREE/d"); do spec="$spec /data/d/$f=$TREE/d/$f"; done
            ;;
    esac
    local S="$TMPD/$tag-$kind.sh" name="$tag-$kind"
    mkscript "$IMG/$kind.want" "$mntcmd" "$prefix" "$S"
    bash tools/mkfsfi/mkfs.sh build "$TMPD/root-$name.img" 20000 /bin/ /proc/ /dev/ /mnt/ /t/ $MKARGS \
        "/t/s.sh=$S" $spec > "$TMPD/mkfs-$name.log" 2>&1 \
        || { bad "[$name] mkfs"; tail -3 "$TMPD/mkfs-$name.log"; return; }
    local drives=(-drive "file=$TMPD/root-$name.img,format=raw,if=ide,index=0")
    if [ -n "$disk" ]; then
        cp --sparse=always "$disk" "$TMPD/live2-$name.img"
        drives+=(-drive "file=$TMPD/live2-$name.img,format=raw,if=ide,index=1")
    fi
    local acc=""
    [ "$OSUM_QEMU_ACCEL" = kvm ] && acc="-cpu host"
    timeout 600 $QEMU_X86 $acc -kernel "$kern" -m 512 \
        -append "osum nokbd vfs script=sh /t/s.sh;exit" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        "${drives[@]}" >/dev/null 2>&1
    tr -d '\r\000' < "$TMPD/$name.txt" > "$TMPD/$name.out"
}

run_held() {
    local kern=$1 tag=$2 name="$2-held"
    local S="$TMPD/$name.sh"
    printf 'echo @@held-start\nsleep 5\nwc -c\necho @@held-end\n' > "$TMPD/held.sh"
    printf 'echo @@ren-start\nsleep 7\nwc -c\necho @@ren-end\n' > "$TMPD/ren.sh"
    {
        echo 'echo @@mount'
        echo 'echo "unlock hdb" > /dev/wlock'
        echo 'umount /mnt'
        echo 'mount /dev/hdb1 /mnt vfat'
        echo 'echo "@@mount-rc=$?"'
        echo 'sh /t/held.sh < /mnt/h/held.bin &'
        echo 'sh /t/ren.sh < /mnt/h/ren.bin &'
        echo 'sleep 1'
        echo 'rm /mnt/h/held.bin'
        echo 'echo "@@rm-rc=$?"'
        echo 'mv /mnt/h/ren.bin /mnt/h/moved.bin'
        echo 'echo "@@mv-rc=$?"'
        echo 'echo @@scan'
        local paths k=0 line=""
        for paths in $(cut -d' ' -f2 "$IMG/fat.want"); do
            line="$line \"/mnt/$paths\""
            k=$((k + 1))
            if [ $((k % 3)) = 0 ]; then echo "shasum$line"; line=""; fi
        done
        [ -z "$line" ] || echo "shasum$line"
        echo 'sleep 11'
        echo 'echo @@renamed'
        echo 'shasum /mnt/h/moved.bin'
        echo 'echo @@end'
        echo 'umount /mnt'
        echo 'sleep 2'
    } > "$S"
    bash tools/mkfsfi/mkfs.sh build "$TMPD/root-$name.img" 20000 /bin/ /proc/ /dev/ /mnt/ /t/ $MKARGS \
        "/t/s.sh=$S" "/t/held.sh=$TMPD/held.sh" "/t/ren.sh=$TMPD/ren.sh" > "$TMPD/mkfs-$name.log" 2>&1 \
        || { bad "[$name] mkfs"; tail -3 "$TMPD/mkfs-$name.log"; return 1; }
    cp --sparse=always "$IMG/fath.disk" "$TMPD/live2-$name.img"
    local acc=""
    [ "$OSUM_QEMU_ACCEL" = kvm ] && acc="-cpu host"
    timeout 600 $QEMU_X86 $acc -kernel "$kern" -m 512 \
        -append "osum nokbd vfs script=sh /t/s.sh;exit" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$TMPD/root-$name.img,format=raw,if=ide,index=0" \
        -drive "file=$TMPD/live2-$name.img,format=raw,if=ide,index=1" >/dev/null 2>&1
    tr -d '\r\000' < "$TMPD/$name.txt" > "$TMPD/$name.out"
}

held_value() {
    awk -v t="$2" '/^ *[0-9]+ *$/{gsub(/ /,""); last=$0} $0 == "@@" t "-end"{print last; exit}' "$1"
}

check_fsck() {
    local name=$1 expect=$2 img="$TMPD/live2-$1.img" rc
    command -v fsck.fat >/dev/null 2>&1 || return 0
    dd if="$img" of="$TMPD/$name.part" bs=512 skip=2048 status=none
    fsck.fat -n "$TMPD/$name.part" > "$TMPD/$name.fsck" 2>&1
    rc=$?
    if [ "$expect" = green ]; then
        [ "$rc" = 0 ] && ok "[$name] host fsck.fat: image clean, no leaked clusters" \
            || { bad "[$name] host fsck.fat rc=$rc"; head -4 "$TMPD/$name.fsck"; }
    fi
}

check_held() {
    local kern=$1 tag=$2 expect=$3 want_unlink=$4 want_rename=$5
    run_held "$kern" "$tag" || return
    local name="$tag-held" out="$TMPD/$tag-held.out" v r sha
    grep -aq '^@@end' "$out" && ok "[$name] script reached the end" || bad "[$name] script did not reach @@end"
    grep -aq '^@@rm-rc=0' "$out" && ok "[$name] unlink of the open file succeeded" || bad "[$name] unlink of the open file failed"
    grep -aq '^@@mv-rc=0' "$out" && ok "[$name] rename of the open file succeeded" || bad "[$name] rename of the open file failed"
    grep -aq '^@@held-end' "$out" && ok "[$name] the unlink holder finished" || bad "[$name] the unlink holder never finished"
    grep -aq '^@@ren-end' "$out" && ok "[$name] the rename holder finished" || bad "[$name] the rename holder never finished"
    v=$(held_value "$out" held)
    r=$(held_value "$out" ren)
    sha=$(awk '/^@@renamed/{on=1; next} on && length($1) == 64 {print $1; exit}' "$out")
    case $want_unlink in
        keep) [ "$v" = "$HELD_SIZE" ] && ok "[$name] unlinked open file: descriptor still reads all $HELD_SIZE bytes" \
                  || bad "[$name] unlinked open file: descriptor reads '$v' bytes, expected $HELD_SIZE" ;;
        neg_foreign) if [ -n "$v" ] && [ "$v" != 0 ] && [ "$v" != "$HELD_SIZE" ]; then ok "[$name] NEGATIVE: the held descriptor reads a foreign file ($v bytes)"
                     else bad "[$name] NEGATIVE: old kernel stays correct ($v bytes), probe is blind"; fi ;;
        neg_lost) [ "$v" != "$HELD_SIZE" ] && ok "[$name] NEGATIVE: clusters freed at unlink, descriptor loses data ('$v' bytes)" \
                  || bad "[$name] NEGATIVE: descriptor still reads everything, probe is blind" ;;
        skip) ;;
    esac
    case $want_rename in
        keep) [ "$r" = "$REN_SIZE" ] && ok "[$name] renamed open file: descriptor still reads all $REN_SIZE bytes" \
                  || bad "[$name] renamed open file: descriptor reads '$r' bytes, expected $REN_SIZE"
              [ "$sha" = "$REN_SHA" ] && ok "[$name] renamed file content equals the host sha256" \
                  || bad "[$name] renamed file content wrong ('$sha')" ;;
        neg) [ "$r" != "$REN_SIZE" ] && ok "[$name] NEGATIVE: rename kills the open descriptor ('$r' bytes)" \
                  || bad "[$name] NEGATIVE: old rename keeps the descriptor, probe is blind" ;;
        skip) ;;
    esac
    check_fsck "$name" "$([ "$expect" = green ] && echo green || echo red)"
}

count_bad() {
    python3 -I - "$@" <<'PYEOF'
import re, sys
wantfile, outfile, prefix = sys.argv[1:4]
want = {}
for l in open(wantfile):
    s, p = l.rstrip("\n").split(" ", 1)
    want[p] = s
seen = 0
bad = 0
for l in open(outfile, errors="replace"):
    m = re.match(r"^([0-9a-f]{64})  (.*)$", l.rstrip("\n"))
    if not m or not m.group(2).startswith(prefix + "/"):
        continue
    seen += 1
    if want.get(m.group(2)[len(prefix) + 1:]) != m.group(1):
        bad += 1
print(seen, bad, len(want))
PYEOF
}

check_kind() {
    local kern=$1 kind=$2 tag=$3 expect=$4 prefix=/mnt
    [ "$kind" = ofs ] && prefix=/data
    runfs "$kern" "$kind" "$tag"
    local name="$tag-$kind"
    [ -f "$TMPD/$name.out" ] || return
    grep -aq '^@@end' "$TMPD/$name.out" && ok "[$name] script reached the end" || bad "[$name] script did not reach @@end"
    if [ "$kind" != ofs ]; then
        grep -aq '^@@mount-rc=0' "$TMPD/$name.out" && ok "[$name] mount ok" || bad "[$name] mount failed"
    fi
    local seen nbad total
    read -r seen nbad total <<< "$(count_bad "$IMG/$kind.want" "$TMPD/$name.out" "$prefix")"
    if [ "$expect" = green ]; then
        [ "$seen" = $((total * 3)) ] && ok "[$name] all $seen reads returned a checksum" \
            || bad "[$name] $seen of $((total * 3)) reads returned a checksum"
        [ "$nbad" = 0 ] && ok "[$name] every checksum equals the host sha256 ($seen reads, 3 passes)" \
            || bad "[$name] $nbad of $seen checksums WRONG"
    else
        if [ "$nbad" -gt 0 ] || [ "$seen" -lt $((total * 3)) ]; then
            ok "[$name] NEGATIVE: old kernel: $nbad wrong checksums, $seen of $((total * 3)) reads answered"
        else
            bad "[$name] NEGATIVE: old kernel stays correct, probe is blind"
        fi
    fi
}

echo "== 3. fixed kernel: reads beyond the node table, every file SHA-checked =="
for k in ${FSSLOTS_KINDS:-ofs fat ext4 ntfs exfat}; do check_kind "$TMPD/new.mb" "$k" new green; done

echo "== 4. negative controls: kernel without the recycle-time drop =="
for k in ${FSSLOTS_OLD_KINDS:-fat ext4 ntfs exfat}; do check_kind "$TMPD/old.mb" "$k" old red; done

echo "== 5. open FAT files: unlink keeps slot + data, rename keeps the descriptor =="
check_held "$TMPD/new.mb" new green keep keep
check_held "$TMPD/oldunlink.mb" oldunlink red neg_foreign skip
check_held "$TMPD/oldfree.mb" oldfree red neg_lost skip
check_held "$TMPD/oldmove.mb" oldmove red skip neg

summary_emit "$pass" "$fail" 48
