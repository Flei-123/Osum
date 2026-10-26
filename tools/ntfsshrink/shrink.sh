echo "== 10. shrink on GPT and MBR disks =="
for t in sgdisk sfdisk; do
    command -v "$t" >/dev/null 2>&1 || { echo "NTFSSHRINK: $t missing"; exit 1; }
done
SHC="$D/shrinkhost"
if "$FIRNC" -o "$SHC" tools/ntfsshrink/shrinkhost.fi > "$D/cc2.log" 2>&1; then
    ok "shrinkhost (lib/ntfsshrink/shrink.fi) builds"
else
    bad "shrinkhost does not build"; head -20 "$D/cc2.log" | sed 's/^/        /'
    echo "NTFSSHRINK: $pass passed, $fail failed"; exit 1
fi

mkdir -p "$D/hf"
head -c 400000 /dev/urandom > "$D/hf/a.bin"
head -c 900 /dev/urandom > "$D/hf/b.bin"
for i in $(seq 1 25); do head -c $((i * 517)) /dev/urandom > "$D/hf/f$i.dat"; done

mksparse() {
    python3 -I - "$1" "$2" <<'PY'
import sys
f = open(sys.argv[1], 'wb'); f.seek(int(sys.argv[2]) * 512 - 1); f.write(b'\0'); f.close()
PY
}

mkdisk() {
    local name=$1 scheme=$2 cs=$3 mib=$4 hf=$5
    local disk="$D/$name.disk" part="$D/$name.part" total=$((mib * 2048)) psize
    mksparse "$disk" "$total"
    if [ "$scheme" = gpt ]; then
        sgdisk -o -n 1:2048:0 -t 1:0700 "$disk" >/dev/null 2>&1
        psize=$(sgdisk -i 1 "$disk" | awk '/Partition size/{print $3}')
    else
        printf 'label: dos\n2048,,7\n' | sfdisk -q "$disk" >/dev/null 2>&1
        psize=$((total - 2048))
    fi
    mksparse "$part" "$psize"
    mkntfs -F -q -s 512 -c "$cs" "$part" >/dev/null 2>&1 || { bad "mkntfs $name"; return 1; }
    for f in "$hf"/*; do ntfscp -f "$part" "$f" "/$(basename "$f")" >/dev/null 2>&1; done
    dd if="$part" of="$disk" bs=512 seek=2048 conv=notrunc 2>/dev/null
    echo "$psize" > "$D/$name.psize"
    cp "$part" "$D/$name.orig"
    rm -f "$part"
}

info_of() {
    "$SHC" "$1" i 2048 x 2>&1 | awk -F= -v k="$2" '$1 == k { print $2 }'
}

variant() {
    local name=$1 scheme=$2 cs=$3 extra=$4
    mkdisk "$name" "$scheme" "$cs" 64 "$D/hf" || return 1
    local psize min target code
    psize=$(cat "$D/$name.psize")
    min=$(info_of "$D/$name.disk" min_sectors)
    target=$((min + extra))
    echo "$target" > "$D/$name.target"
    cp "$D/$name.disk" "$D/$name.d1"
    "$SHC" "$D/$name.d1" r 2048 "$D/$name.d1" "$target" > "$D/$name.run" 2>&1
    code=$(awk -F= '$1 == "code" { print $2 }' "$D/$name.run")
    if [ "$code" != 0 ]; then bad "$name: shrink to $target sectors returned code $code"; return 1; fi
    awk -F= '$1 == "writes" { print $2 }' "$D/$name.run" > "$D/$name.writes"
    if res=$(python3 -I tools/ntfsshrink/shrinkcheck.py "$D/$name.d1" "$scheme" 2048 "$psize" "$((target))" "$D/$name.orig" "$D/hf" "$D/unit" tools/ntfsshrink/check.py 2>&1); then
        ok "$name ($scheme, cluster $cs): $psize -> $target sectors in $(cat "$D/$name.writes") writes; table, boot, backup, bitmap padding, \$Bad, flags, ${NFILES} file hashes"
    else
        bad "$name: $(echo "$res" | tr '\n' ';')"
    fi
    cp "$D/$name.d1" "$D/$name.d2"
    "$SHC" "$D/$name.d2" r 2048 "$D/$name.d2" "$target" > "$D/$name.run2" 2>&1
    if grep -aq '^code=14' "$D/$name.run2" && cmp -s "$D/$name.d1" "$D/$name.d2"; then
        ok "$name: second run reports 'already this size' and writes nothing"
    else
        bad "$name: second run $(tr '\n' ' ' < "$D/$name.run2")"
    fi
}

NFILES=$(ls "$D/hf" | wc -l)
variant gpt4k gpt 4096 2051
variant gpt512 gpt 512 2051
variant gpt64k gpt 65536 2051
variant mbr4k mbr 4096 2051

echo "== 11. power loss at every write =="
fuzz() {
    local name=$1 scheme=$2 expect=$3
    shift 3
    local w="$D/fz_$name"
    mkdir -p "$w"
    res=$(python3 -I tools/ntfsshrink/shrinkfuzz.py "$SHC" "$D/$name.disk" "$D/$name.d1" "$scheme" 2048 "$(cat "$D/$name.psize")" "$(cat "$D/$name.target")" "$(cat "$D/$name.writes")" "$D/hf" "$w" "$@" 2>&1)
    local rc=$?
    rm -rf "$w"
    if [ "$expect" = green ]; then
        if [ $rc -eq 0 ]; then ok "$name: $(echo "$res" | head -1): recover + shrink again = byte-identical to the undisturbed run, old volume intact before the commit"; else bad "$name fuzz: $(echo "$res" | tr '\n' ';')"; fi
    else
        if [ $rc -ne 0 ]; then ok "counter-proof $name: without healing the crashed images differ ($(echo "$res" | head -1))"; else bad "counter-proof $name: unhealed images were accepted"; fi
    fi
}
fuzz gpt4k gpt green nested
fuzz mbr4k mbr green
fuzz gpt4k gpt red noheal

echo "== 12. refused volumes leave the disk untouched =="
refuse2() {
    local label=$1 want=$2 target=$3 patch=$4 disk="$D/gpt4k.disk"
    cp "$disk" "$D/rf.disk"
    python3 -I - "$D/rf.disk" "$patch" <<'PY'
import struct, sys
f = open(sys.argv[1], 'r+b')
rd = lambda o, n: (f.seek(o), f.read(n))[1]
wr = lambda o, b: (f.seek(o), f.write(b))
base = 2048 * 512
kind = sys.argv[2]
if kind == 'zero': wr(base, b'\0' * 512)
elif kind == 'fve': wr(base + 3, b'-FVE-FS-')
elif kind == 'dirty':
    mft = struct.unpack('<Q', rd(base + 0x30, 8))[0] * 4096
    o = base + mft + 3 * 1024 + 418
    wr(o, bytes([rd(o, 1)[0] | 1]))
f.close()
PY
    cp "$D/rf.disk" "$D/rf.before"
    "$SHC" "$D/rf.disk" r 2048 "$D/rf.disk" "$target" > "$D/rf.out" 2>&1
    local got
    got=$(awk -F= '$1 == "code" { print $2 }' "$D/rf.out")
    if [ "$got" = "$want" ] && cmp -s "$D/rf.disk" "$D/rf.before"; then ok "$label -> code $got, disk bytes unchanged"; else bad "$label: want $want got '$got' unchanged=$(cmp -s "$D/rf.disk" "$D/rf.before" && echo yes || echo no)"; fi
}
T=$(cat "$D/gpt4k.target")
PS=$(cat "$D/gpt4k.psize")
MIN=$(info_of "$D/gpt4k.disk" min_sectors)
refuse2 "target inside the 16 MiB reserve (no room even after relocation)" 9 8192 none
refuse2 "target equal to the partition" 14 "$PS" none
refuse2 "target larger than the partition" 10 $((PS + 8)) none
refuse2 "target below 1 MiB" 10 1000 none
refuse2 "not NTFS (zeroed boot sector)" 2 "$T" zero
refuse2 "BitLocker signature" 3 "$T" fve
refuse2 "dirty volume" 6 "$T" dirty

mkdir -p "$D/bf"
head -c 48000000 /dev/zero | tr '\0' 'x' > "$D/bf/big.dat"
cp "$D/gpt4k.orig" "$D/bigend.part"
ntfscp -f "$D/bigend.part" "$D/bf/big.dat" /big.dat >/dev/null 2>&1
cp "$D/gpt4k.disk" "$D/bigend.disk"
dd if="$D/bigend.part" of="$D/bigend.disk" bs=512 seek=2048 conv=notrunc 2>/dev/null
cp "$D/bigend.disk" "$D/bigend.before"
"$SHC" "$D/bigend.disk" r 2048 "$D/bigend.disk" "$T" > "$D/bigend.out" 2>&1
if grep -aq '^code=9' "$D/bigend.out" && cmp -s "$D/bigend.disk" "$D/bigend.before"; then ok "data at the end of the volume -> code 9, disk bytes unchanged"; else bad "data at the end: $(tr '\n' ' ' < "$D/bigend.out")"; fi
rm -f "$D/bigend.part" "$D/bigend.disk" "$D/bigend.before"

hib_case() {
    local label=$1 want=$2 head=$3
    cp "$D/gpt4k.orig" "$D/h.part"
    printf '%s' "$head" > "$D/h.dat"; head -c 60000 /dev/urandom >> "$D/h.dat"
    ntfscp -f "$D/h.part" "$D/h.dat" /hiberfil.sys >/dev/null 2>&1
    cp "$D/gpt4k.disk" "$D/h.disk"
    dd if="$D/h.part" of="$D/h.disk" bs=512 seek=2048 conv=notrunc 2>/dev/null
    "$SHC" "$D/h.disk" r 2048 "$D/h.disk" "$T" > "$D/h.out" 2>&1
    if grep -aq "^code=$want" "$D/h.out"; then ok "$label -> code $want"; else bad "$label: $(tr '\n' ' ' < "$D/h.out")"; fi
    rm -f "$D/h.part" "$D/h.disk" "$D/h.dat"
}
hib_case "hiberfil.sys with hibr header" 7 hibr
hib_case "hiberfil.sys with wake header (Fast Startup off)" 0 wake

echo "== 13. mutations of the library must turn red =="
mutate() {
    local label=$1 file=$2 expr=$3
    rm -rf "$D/mutlib"; cp -r lib "$D/mutlib"
    sed -i "$expr" "$D/mutlib/ntfsshrink/$file"
    if cmp -s "lib/ntfsshrink/$file" "$D/mutlib/ntfsshrink/$file"; then bad "mutation '$label' did not change the source"; return; fi
    if ! FIRNLIB="$D/mutlib" "$FIRNC" -o "$D/mutexe" tools/ntfsshrink/shrinkhost.fi > "$D/mut.log" 2>&1; then bad "mutation '$label' does not build"; return; fi
    cp "$D/gpt4k.disk" "$D/m.disk"
    "$D/mutexe" "$D/m.disk" r 2048 "$D/m.disk" "$T" > "$D/m.out" 2>&1
    if python3 -I tools/ntfsshrink/shrinkcheck.py "$D/m.disk" gpt 2048 "$PS" "$T" "$D/gpt4k.orig" "$D/hf" "$D/unit" tools/ntfsshrink/check.py > "$D/m.chk" 2>&1; then
        bad "mutation '$label' was not detected"
    else
        ok "mutation '$label' detected ($(head -1 "$D/m.chk" | cut -c1-60))"
    fi
    rm -f "$D/m.disk" "$D/mutexe"
}
mutate "bitmap padding skipped" shrink.fi 's|r = steps.fix_bitmap(v, b, c_new)|r = codes.E_OK|'
mutate "\$Bad run skipped" shrink.fi 's|r = steps.fix_bad(v, b, c_new)|r = codes.E_OK|'
mutate "partition table skipped" shrink.fi 's|r = ptab.apply(.*|r = codes.E_OK|'
mutate "dirty flag never cleared" shrink.fi 's|r = steps.set_dirty(v, b, false)|r = codes.E_OK|'
mutate "old backup boot sector kept" shrink.fi 's|if !intent.clear_at((\*v).wr, (\*v).base + (\*it).old_s, scratch + O_INT) {|if false {|'
mutate "intent sector kept" shrink.fi 's|if !intent.clear_at((\*v).wr, (\*v).base + (\*it).new_s + 1, scratch + O_INT) {|if false {|'
mutate "new backup boot sector skipped" shrink.fi 's|r = steps.write_boot(&v, b.sec, s_new, s_new)|r = codes.E_OK|'
mutate "boot sector commit skipped" shrink.fi 's|r = steps.write_boot(&v, b.sec, 0, s_new)|r = codes.E_OK|'
rm -rf "$D/mutlib"
