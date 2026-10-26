#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
for t in mkntfs ntfsinfo ntfscat ntfscp ntfsls ntfsresize ntfsfix sgdisk mkfs.vfat mcopy mdir mtype python3 qemu-system-x86_64; do
    command -v "$t" >/dev/null 2>&1 || { echo "SHRINKINST: $t missing"; exit 1; }
done
OUT=$(mktemp -d); export OUT
trap 'rm -rf "$OUT"' EXIT
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
FIRNC=vendor/firn/bin/firnc

ESP_START=2048
ESP_SECT=69632
NTFS_START=$((ESP_START + ESP_SECT))
NTFS_SECT=409600
NTFS_END=$((NTFS_START + NTFS_SECT - 1))
DISK_SECT=$((NTFS_END + 1 + 2048))
FREE_MIB=44
FREE_SECT=$((FREE_MIB * 2048))
ALIGN=2048
EXPECT=$(( ( (NTFS_START + NTFS_SECT - FREE_SECT + ALIGN - 1) / ALIGN) * ALIGN - NTFS_START ))
RUN_LIMIT=${RUN_LIMIT:-900}

mksparse() {
    python3 -I - "$1" "$2" <<'PY'
import sys
f = open(sys.argv[1], 'wb'); f.seek(int(sys.argv[2]) * 512 - 1); f.write(b'\0'); f.close()
PY
}

splice() {
    dd if="$2" of="$1" bs=512 seek="$NTFS_START" conv=notrunc status=none
}

sha() { sha256sum < "$1" | cut -d' ' -f1; }

serial_lines() {
    tr -d '\000' < "$1" 2>/dev/null | grep -a '^dual:' | head -"${2:-12}" | sed 's/^/        /'
}

echo "== 1. build kernel and dualcli =="
if PROGS="sh ls cat echo sync dualcli" APPS="" ZIEL_MIB=64 bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 && [ -x "$OUT/bin/dualcli" ]; then
    ok "kernel and dualcli build"
else
    bad "build failed"; tail -15 "$OUT/build.log" | sed 's/^/        /'
    echo "SHRINKINST: $pass passed, $fail failed"; exit 1
fi

echo "== 2. foreign disk: ESP + NTFS with files =="
HF="$OUT/hf"
mkdir -p "$HF"
head -c 3000000 /dev/urandom > "$HF/a.bin"
head -c 777 /dev/urandom > "$HF/b.bin"
for i in $(seq 1 20); do head -c $((i * 913)) /dev/urandom > "$HF/f$i.dat"; done
mksparse "$OUT/ntfs.part" "$NTFS_SECT"
mkntfs -F -q -s 512 -c 4096 "$OUT/ntfs.part" >/dev/null 2>&1 || { bad "mkntfs"; echo "SHRINKINST: $pass passed, $fail failed"; exit 1; }
for f in "$HF"/*; do ntfscp -f "$OUT/ntfs.part" "$f" "/$(basename "$f")" >/dev/null 2>&1; done
mksparse "$OUT/pristine.img" "$DISK_SECT"
sgdisk -o "$OUT/pristine.img" >/dev/null 2>&1
sgdisk -n "1:$ESP_START:$((ESP_START + ESP_SECT - 1))" -t 1:EF00 -c 1:"EFI System Partition" "$OUT/pristine.img" >/dev/null 2>&1
sgdisk -n "2:$NTFS_START:$NTFS_END" -t 2:0700 -c 2:"Basic data partition" "$OUT/pristine.img" >/dev/null 2>&1
dd if=/dev/zero of="$OUT/esp.part" bs=512 count="$ESP_SECT" status=none
mkfs.vfat -F 32 -n SYSTEM "$OUT/esp.part" >/dev/null 2>&1
mmd -i "$OUT/esp.part" ::/EFI ::/EFI/Microsoft ::/EFI/Microsoft/Boot >/dev/null 2>&1
printf 'FOREIGN BOOT MANAGER PLACEHOLDER\n' > "$OUT/bm.bin"
printf 'This file belongs to the foreign system and must survive.\n' > "$OUT/bcd.bin"
mcopy -o -i "$OUT/esp.part" "$OUT/bm.bin" ::/EFI/Microsoft/Boot/bootmgfw.efi
mcopy -o -i "$OUT/esp.part" "$OUT/bcd.bin" ::/EFI/Microsoft/Boot/BCD
dd if="$OUT/esp.part" of="$OUT/pristine.img" bs=512 seek="$ESP_START" conv=notrunc status=none
splice "$OUT/pristine.img" "$OUT/ntfs.part"
rm -f "$OUT/esp.part"
echo "   disk $DISK_SECT sectors, ESP $ESP_START+$ESP_SECT, NTFS $NTFS_START+$NTFS_SECT, expected new size $EXPECT"
sgdisk -v "$OUT/pristine.img" | grep -q 'No problems found' && ok "foreign disk has a valid GPT" || bad "foreign disk GPT"
ntfsfix -n "$OUT/ntfs.part" >/dev/null 2>&1 && ok "foreign NTFS is clean (ntfsfix)" || bad "foreign NTFS not clean"

run_qemu() {
    local name=$1 img=$2 script=$3
    ZWEITE_PLATTE="$img" bash tools/install/oneshot.sh "$name" iso "$script" "$RUN_LIMIT" >/dev/null 2>&1
}

echo "== 3. dry run (no --ja) leaves the disk untouched =="
cp "$OUT/pristine.img" "$OUT/probe.img"
BEFORE=$(sha "$OUT/probe.img")
run_qemu probe "$OUT/probe.img" "dualcli /dev/hdb --free $FREE_MIB;exit"
serial_lines "$OUT/probe.txt" 14
grep -aq '^dual: recover=0' "$OUT/probe.txt" && ok "no pending recovery on a clean disk" || bad "recover line missing or nonzero"
grep -aq "^dual: shoffer 2 $NTFS_SECT" "$OUT/probe.txt" && ok "offers to shrink partition 2 ($NTFS_SECT sectors)" || bad "no shoffer for partition 2"
grep -aq "^dual: shplan $EXPECT $FREE_SECT" "$OUT/probe.txt" && ok "plan equals the independent oracle: $EXPECT sectors, $FREE_SECT free" || bad "shplan differs from oracle $EXPECT"
[ "$(sha "$OUT/probe.img")" = "$BEFORE" ] && ok "dry run: disk byte-identical" || bad "dry run wrote to the disk"
mv "$OUT/probe.img" "$OUT/skip.img"

echo "== 4. shrink and install =="
cp "$OUT/pristine.img" "$OUT/main.img"
ESP_BEFORE=$(dd if="$OUT/main.img" bs=512 skip="$ESP_START" count="$ESP_SECT" status=none | sha256sum | cut -d' ' -f1)
run_qemu main "$OUT/main.img" "dualcli /dev/hdb --free $FREE_MIB --ja --name hdb;exit"
serial_lines "$OUT/main.txt" 24
grep -aq '^dual: shresult=0' "$OUT/main.txt" && ok "shrink reports success" || bad "shrink did not report success"
grep -aq '^dual: shrunk ' "$OUT/main.txt" && ok "table re-read after the shrink" || bad "no re-read of the table"
grep -aq '^dual: done' "$OUT/main.txt" && ok "installation finished in the freed space" || bad "installation not finished"
res=$(python3 -I tools/shrinkinst/check.py "$OUT/main.img" "$EXPECT" "$HF" --installed 2>&1)
[ "$res" = ALLOK ] && ok "host oracle: sgdisk -v, partition end = target, ntfsresize -i, ntfsfix -n, flags clean, $(ls "$HF" | wc -l) file hashes, partition 3 OSUM behind it" || bad "host oracle: $(echo "$res" | tr '\n' ';')"
mdir -i "$OUT/main.img@@$((ESP_START * 512))" ::/EFI/Microsoft/Boot > "$OUT/esp-list.txt" 2>&1
grep -qi bootmgfw "$OUT/esp-list.txt" && grep -qi BCD "$OUT/esp-list.txt" && ok "foreign boot files still in the ESP" || bad "foreign boot files missing"
[ "$(mtype -i "$OUT/main.img@@$((ESP_START * 512))" ::/EFI/Microsoft/Boot/BCD 2>/dev/null)" = "$(cat "$OUT/bcd.bin")" ] && ok "foreign BCD content unchanged" || bad "foreign BCD content changed"

echo "== 5. counter-proofs for the host oracle =="
res=$(python3 -I tools/shrinkinst/check.py "$OUT/pristine.img" "$EXPECT" "$HF" 2>&1)
[ "$res" != ALLOK ] && ok "unshrunk disk is rejected ($(echo "$res" | head -1))" || bad "oracle accepted the unshrunk disk"
res=$(python3 -I tools/shrinkinst/check.py "$OUT/skip.img" "$EXPECT" "$HF" 2>&1)
[ "$res" != ALLOK ] && ok "skipped shrink (dry-run disk) is rejected" || bad "oracle accepted the skipped shrink"
cp "$OUT/main.img" "$OUT/flip.img"
python3 -I - "$OUT/flip.img" "$NTFS_START" "$HF/a.bin" <<'PY'
import sys
f = open(sys.argv[1], 'r+b'); base = int(sys.argv[2]) * 512
head = open(sys.argv[3], 'rb').read(64)
f.seek(base); data = f.read(300 * 1048576); at = data.find(head)
assert at >= 0
f.seek(base + at + 100); b = f.read(1); f.seek(base + at + 100); f.write(bytes([b[0] ^ 255])); f.close()
PY
res=$(python3 -I tools/shrinkinst/check.py "$OUT/flip.img" "$EXPECT" "$HF" 2>&1)
[ "$res" != ALLOK ] && ok "one flipped data byte is detected" || bad "oracle missed a flipped data byte"
rm -f "$OUT/flip.img" "$OUT/skip.img"

echo "== 6. refused volumes: disk stays byte-identical =="
refuse_case() {
    local name=$1 want=$2 label=$3 part=$4
    cp "$OUT/pristine.img" "$OUT/$name.img"
    splice "$OUT/$name.img" "$part"
    local before
    before=$(sha "$OUT/$name.img")
    run_qemu "$name" "$OUT/$name.img" "dualcli /dev/hdb --free $FREE_MIB --ja --name hdb;exit"
    serial_lines "$OUT/$name.txt" 6
    if grep -aq "^dual: shrefuse $want\$" "$OUT/$name.txt"; then ok "$label -> shrefuse $want"; else bad "$label: expected shrefuse $want"; fi
    if grep -aq '^dual: done' "$OUT/$name.txt"; then bad "$label: installed anyway"; else ok "$label: no installation"; fi
    if [ "$(sha "$OUT/$name.img")" = "$before" ]; then ok "$label: disk byte-identical"; else bad "$label: disk changed"; fi
    rm -f "$OUT/$name.img"
}

head -c 60000 /dev/urandom > "$OUT/rand.dat"
cp "$OUT/ntfs.part" "$OUT/hib.part"
{ printf 'hibr'; cat "$OUT/rand.dat"; } > "$OUT/hib.dat"
ntfscp -f "$OUT/hib.part" "$OUT/hib.dat" /hiberfil.sys >/dev/null 2>&1
refuse_case hibr 7 "hibernated Windows (hibr header)" "$OUT/hib.part"
rm -f "$OUT/hib.part" "$OUT/hib.dat"

cp "$OUT/ntfs.part" "$OUT/dirty.part"
python3 -I - "$OUT/dirty.part" <<'PY'
import struct, sys
f = open(sys.argv[1], 'r+b')
rd = lambda o, n: (f.seek(o), f.read(n))[1]
wr = lambda o, b: (f.seek(o), f.write(b))
mft = struct.unpack('<Q', rd(0x30, 8))[0] * 4096
o = mft + 3 * 1024 + 418
wr(o, bytes([rd(o, 1)[0] | 1]))
f.close()
PY
refuse_case dirty 6 "dirty volume flag" "$OUT/dirty.part"
rm -f "$OUT/dirty.part"

cp "$OUT/ntfs.part" "$OUT/fve.part"
python3 -I - "$OUT/fve.part" <<'PY'
import sys
f = open(sys.argv[1], 'r+b'); f.seek(3); f.write(b'-FVE-FS-'); f.close()
PY
refuse_case fve 3 "BitLocker signature" "$OUT/fve.part"
rm -f "$OUT/fve.part"

cp "$OUT/ntfs.part" "$OUT/full.part"
python3 -I -c "open(\"$OUT/full1.dat\", \"wb\").write(b\"x\" * 70000000); open(\"$OUT/full2.dat\", \"wb\").write(b\"x\" * 90000000)"
ntfscp -f "$OUT/full.part" "$OUT/full1.dat" /full1.dat >/dev/null 2>&1
ntfscp -f "$OUT/full.part" "$OUT/full2.dat" /full2.dat >/dev/null 2>&1
refuse_case full 9 "volume too full to free $FREE_MIB MiB" "$OUT/full.part"
rm -f "$OUT/full.part" "$OUT/full1.dat" "$OUT/full2.dat"

echo "== 7. recovery of an interrupted shrink at the next start =="
SHC="$OUT/shrinkhost"
if "$FIRNC" -o "$SHC" tools/ntfsshrink/shrinkhost.fi > "$OUT/cc.log" 2>&1; then
    ok "shrinkhost builds"
else
    bad "shrinkhost does not build"; head -10 "$OUT/cc.log" | sed 's/^/        /'
    echo "SHRINKINST: $pass passed, $fail failed"; exit 1
fi
cp "$OUT/pristine.img" "$OUT/clean.img"
"$SHC" "$OUT/clean.img" r "$NTFS_START" "$OUT/clean.img" "$EXPECT" > "$OUT/clean.out" 2>&1
WRITES=$(awk -F= '$1 == "writes" { print $2 }' "$OUT/clean.out")
[ "${WRITES:-0}" -gt 0 ] && ok "host reference shrink: $WRITES writes" || { bad "host reference shrink failed"; echo "SHRINKINST: $pass passed, $fail failed"; exit 1; }
recover_case() {
    local name=$1 mode=$2 label=$3 k
    k=$(python3 -I tools/shrinkinst/crashpick.py "$SHC" "$OUT/pristine.img" "$NTFS_START" "$NTFS_SECT" "$EXPECT" "$WRITES" "$mode" "$OUT")
    if [ -z "$k" ]; then bad "$label: no crash point found"; return; fi
    cp "$OUT/pristine.img" "$OUT/$name.img"
    "$SHC" "$OUT/$name.img" r "$NTFS_START" "$OUT/$name.img" "$EXPECT" "$k" "$([ "$mode" = torn ] && echo 1 || echo 0)" > /dev/null 2>&1
    sgdisk -v "$OUT/$name.img" 2>&1 | grep -q 'No problems found' && [ "$mode" = torn ] && { bad "$label: crash image has a clean GPT"; return; }
    run_qemu "$name" "$OUT/$name.img" "dualcli /dev/hdb --free $FREE_MIB;exit"
    serial_lines "$OUT/$name.txt" 8
    if grep -aq '^dual: recover=[1-9]' "$OUT/$name.txt"; then ok "$label (write $k): dualcli recovers at start"; else bad "$label: no recovery reported"; fi
    if cmp -s "$OUT/$name.img" "$OUT/clean.img"; then ok "$label: disk byte-identical to the undisturbed shrink"; else bad "$label: disk differs from the undisturbed shrink"; fi
    res=$(python3 -I tools/shrinkinst/check.py "$OUT/$name.img" "$EXPECT" "$HF" 2>&1)
    [ "$res" = ALLOK ] && ok "$label: host oracle passes" || bad "$label: host oracle: $(echo "$res" | tr '\n' ';')"
    rm -f "$OUT/$name.img"
}
recover_case rec_intent intent "intent present, GPT still valid"
recover_case rec_torn torn "GPT torn mid-write"

echo "== 8. data beyond the target end: relocation, progress, packed size =="
python3 -I tools/ntfsshrink/endmake.py "$OUT" inst4k "$NTFS_SECT" >/dev/null && ok "end-placed NTFS built (filler freed, data behind $((NTFS_SECT / 2048 - FREE_MIB)) MiB)" || bad "endmake inst4k"
mv "$OUT/inst4k.part" "$OUT/endp.part"
cp "$OUT/pristine.img" "$OUT/reloc.img"
splice "$OUT/reloc.img" "$OUT/endp.part"
ntfsfix -n "$OUT/endp.part" >/dev/null 2>&1 && ok "end-placed NTFS is clean" || bad "end-placed NTFS not clean"
python3 -I tools/shrinkinst/check.py "$OUT/reloc.img" "$EXPECT" "$OUT/inst4k.files" > "$OUT/reloc.pre" 2>&1
[ "$(head -1 "$OUT/reloc.pre")" != ALLOK ] && ok "oracle rejects the end-placed disk before the shrink" || bad "oracle accepted the unshrunk end-placed disk"
run_qemu reloc "$OUT/reloc.img" "dualcli /dev/hdb --free $FREE_MIB --ja --name hdb;exit"
serial_lines "$OUT/reloc.txt" 24
grep -aq '^dual: shresult=0' "$OUT/reloc.txt" && ok "shrink with relocation reports success" || bad "relocating shrink failed ($(grep -a '^dual: sh' "$OUT/reloc.txt" | tr '\n' ' ' | cut -c1-120))"
tr -d '\000' < "$OUT/reloc.txt" | grep -a '^dual: shprog ' | awk '{print $3}' > "$OUT/prog.txt"
if [ "$(wc -l < "$OUT/prog.txt")" -ge 4 ] && sort -n -c "$OUT/prog.txt" 2>/dev/null && [ "$(tail -1 "$OUT/prog.txt")" = 100 ]; then ok "progress lines rise monotonically to 100 ($(tr '\n' ' ' < "$OUT/prog.txt"))"; else bad "progress lines: $(tr '\n' ' ' < "$OUT/prog.txt")"; fi
grep -aq '^dual: done' "$OUT/reloc.txt" && ok "installation finished after the relocating shrink" || bad "installation not finished after relocation"
res=$(python3 -I tools/shrinkinst/check.py "$OUT/reloc.img" "$EXPECT" "$OUT/inst4k.files" --installed 2>&1)
[ "$res" = ALLOK ] && ok "host oracle: relocated data, mirror, all file hashes, ntfsresize/ntfsfix clean" || bad "host oracle: $(echo "$res" | tr '\n' ';' | cut -c1-300)"
cp "$OUT/reloc.img" "$OUT/relocflip.img"
python3 -I - "$OUT/relocflip.img" "$NTFS_START" "$OUT/inst4k.files/big.bin" <<'PY'
import sys
f = open(sys.argv[1], 'r+b'); base = int(sys.argv[2]) * 512
head = open(sys.argv[3], 'rb').read(64)
f.seek(base); data = f.read(150 * 1048576); at = data.find(head)
assert at >= 0
f.seek(base + at + 50); b = f.read(1); f.seek(base + at + 50); f.write(bytes([b[0] ^ 255])); f.close()
PY
res=$(python3 -I tools/shrinkinst/check.py "$OUT/relocflip.img" "$EXPECT" "$OUT/inst4k.files" --installed 2>&1)
[ "$res" != ALLOK ] && ok "a flipped byte in relocated data is detected" || bad "oracle missed a flipped byte in relocated data"
rm -f "$OUT/reloc.img" "$OUT/relocflip.img" "$OUT/endp.part"
echo "SHRINKINST: $pass passed, $fail failed"
[ "$fail" = 0 ]
