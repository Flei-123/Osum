#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/marke-env.sh"
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export BOOT_KERNEL_COPY=1
. tools/lib/qemu.sh
for t in sgdisk mkntfs mkfs.vfat mdir python3 sha256sum; do
    command -v "$t" >/dev/null 2>&1 || { echo "OSUMREUSE: $t missing"; exit 1; }
done
OUT=$(mktemp -d); QP=""
trap 'kill $QP 2>/dev/null; rm -rf "$OUT"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
BAU=${BAU:-}
if [ -z "$BAU" ]; then
    BAU="$OUT/bau"; mkdir -p "$BAU"
    bash tools/usbimg/build.sh "$BAU" > "$OUT/bau.log" 2>&1 || { echo "build failed"; tail -n 5 "$OUT/bau.log"; exit 1; }
fi

run() {
    local disk=$1 ser=$2 args=$3 stop=$4 limit=$5
    : > "$ser"
    timeout "$limit" $QEMU_X86 -m 512 -kernel "$BAU/osum.mb" -initrd "$BAU/root.img" \
        -append "modfs osum vfs gfx wm wig wmhold wmdauer wighalt=1500 nosched noproc nofs lang=de uiscale=1 wigapp=/bin/installer,$args" \
        -serial "file:$ser" -display none -no-reboot \
        -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
        -drive "file=$disk,format=raw,if=ide,index=0" > "$ser.qemu" 2>&1 &
    QP=$!
    local i=0
    while [ $i -lt $((limit * 2)) ]; do
        tr -d '\000' < "$ser" 2>/dev/null | grep -aq "$stop" && break
        kill -0 "$QP" 2>/dev/null || break
        sleep 0.5; i=$((i + 1))
    done
    sleep 1
    kill $QP 2>/dev/null; wait $QP 2>/dev/null; QP=""
}
field() { tr -d '\000' < "$1" | grep -a "^installer: view $2=" | tail -n 1 | sed "s/^installer: view $2=//"; }
psha() { dd if="$1" bs=512 skip="$2" count="$3" status=none | sha256sum | cut -d' ' -f1; }
table() { sgdisk -p "$1" | awk '/^ +[0-9]+ /{print $1,$2,$3,$7}'; }

ESP_START=2048; ESP_SECT=409600; MSR_START=411648; MSR_SECT=32768
NTFS_START=444416; NTFS_SECT=409600; OSUM_MIB=64; OSUM_START=854016; OSUM_SECT=$((OSUM_MIB * 2048))
REC_START=$((OSUM_START + OSUM_SECT)); REC_SECT=40960

echo "== 1. HP layout: Recovery behind OSUM, ESP shared, free gap about 1 MiB =="
mkdir -p "$OUT/h"
bash tools/gptview/mkhp.sh "$OUT/h" 0 "$OSUM_MIB" && ok "HP-like disk with leftover OSUM partition (#5) before recovery (#4)" || { bad "disk"; echo "OSUMREUSE: $pass passed, $fail failed"; exit 1; }
cp "$OUT/h/disk.img" "$OUT/pristine.img"
T0=$(table "$OUT/pristine.img")
printf '%s\n' "$T0" | sed 's/^/        /'
S_MSR=$(psha "$OUT/pristine.img" $MSR_START $MSR_SECT); S_NTFS=$(psha "$OUT/pristine.img" $NTFS_START $NTFS_SECT); S_REC=$(psha "$OUT/pristine.img" $REC_START $REC_SECT)
S_OSUM=$(psha "$OUT/pristine.img" $OSUM_START 64)
sum0=$(sha256sum < "$OUT/pristine.img" | cut -d' ' -f1)

echo "== 2. view: reinstall enabled, beside disabled =="
run "$OUT/pristine.img" "$OUT/v.txt" "reuse" '^installer: view esp=' 300
rows=$(field "$OUT/v.txt" rows); re=$(field "$OUT/v.txt" reuse); beside=$(field "$OUT/v.txt" beside); art=$(field "$OUT/v.txt" art)
printf '        rows=%s reuse=%s beside=%s\n        art=%s\n' "$rows" "$re" "$beside" "$art"
[ "$rows" = 5 ] && ok "5 partitions listed" || bad "rows=$rows"
[ "$re" = 1 ] && ok "reinstall enabled with ${MARKE_PRODUKT} row selected" || bad "reuse=$re"
[ "$beside" = 0 ] && ok "beside stays disabled (gap below 32 MiB)" || bad "beside=$beside"
case "$art" in *"${MARKE_PRODUKT}"*) ok "type column names ${MARKE_PRODUKT}" ;; *) bad "art=$art" ;; esac
[ "$(sha256sum < "$OUT/pristine.img" | cut -d' ' -f1)" = "$sum0" ] && ok "disk byte-identical after viewing" || bad "view wrote to the disk"

echo "== 3. reinstall over #5 =="
cp "$OUT/pristine.img" "$OUT/main.img"
run "$OUT/main.img" "$OUT/r.txt" "reuse,now" '^installer: \(done\|ERROR\)' 1500
tr -d '\000' < "$OUT/r.txt" | grep -a '^installer: \(newpart\|step\|done\|ERROR\|at=\|esp=\|menu=\)' | head -n 14 | sed 's/^/        /'
tr -d '\000' < "$OUT/r.txt" | grep -aq '^installer: done' && ok "installer reports done" || bad "installer did not finish"
tr -d '\000' < "$OUT/r.txt" | grep -aq '^installer: newpart 5 ' && ok "target is partition 5" || bad "wrong target partition"
T1=$(table "$OUT/main.img")
[ "$T1" = "$T0" ] && ok "partition table unchanged (5 entries, same start/end)" || bad "table differs: $T1"
sgdisk -v "$OUT/main.img" 2>&1 | grep -q 'No problems found' && ok "sgdisk -v clean" || bad "sgdisk -v not clean"
[ "$(psha "$OUT/main.img" $MSR_START $MSR_SECT)" = "$S_MSR" ] && ok "MSR untouched" || bad "MSR changed"
[ "$(psha "$OUT/main.img" $NTFS_START $NTFS_SECT)" = "$S_NTFS" ] && ok "BitLocker/NTFS partition untouched" || bad "NTFS partition changed"
[ "$(psha "$OUT/main.img" $REC_START $REC_SECT)" = "$S_REC" ] && ok "Recovery partition untouched" || bad "Recovery changed"
[ "$(psha "$OUT/main.img" $OSUM_START 64)" != "$S_OSUM" ] && ok "OSUM partition rewritten" || bad "OSUM partition unchanged"
mdir -i "$OUT/main.img@@$((ESP_START * 512))" ::/EFI/BOOT > "$OUT/esp.txt" 2>&1
grep -qi 'BOOTX64' "$OUT/esp.txt" && ok "boot loader written to the existing ESP" || bad "no boot loader on ESP: $(head -n 2 "$OUT/esp.txt" | tr '\n' ' ')"
python3 -I - "$OUT/main.img" <<'PY' && ok "persistent log in the disk gap has the log magic" || bad "no persistent log in the disk gap"
import sys
f = open(sys.argv[1], 'rb'); f.seek(40 * 512); b = f.read(16 * 512)
sys.exit(0 if b[:4] == b'OSLG' and b'copy' in b else 1)
PY

echo "== 4. delete leftover =="
cp "$OUT/pristine.img" "$OUT/del.img"
run "$OUT/del.img" "$OUT/d.txt" "reuse,now,rmleft" '^installer: deleted=' 300
tr -d '\000' < "$OUT/d.txt" | grep -a '^installer: \(deleted\|view rows\)' | sed 's/^/        /'
tr -d '\000' < "$OUT/d.txt" | grep -aq '^installer: deleted=1' && ok "delete reports success" || bad "delete failed"
T2=$(table "$OUT/del.img")
[ "$(printf '%s\n' "$T2" | wc -l)" = 4 ] && ok "partition 5 removed, 4 entries remain" || bad "table: $T2"
printf '%s\n' "$T2" | grep -q "^4 $REC_START" && ok "Recovery entry intact" || bad "Recovery entry changed"
sgdisk -v "$OUT/del.img" 2>&1 | grep -q 'No problems found' && ok "sgdisk -v clean after delete (both tables, CRCs)" || bad "sgdisk -v not clean after delete"
[ "$(psha "$OUT/del.img" $REC_START $REC_SECT)" = "$S_REC" ] && ok "Recovery data untouched by delete" || bad "Recovery data changed"

echo "== 5. counter-proof: OSUM leftover below 32 MiB is refused =="
mkdir -p "$OUT/s"
bash tools/gptview/mkhp.sh "$OUT/s" 0 8 && ok "disk with 8 MiB ${MARKE_PRODUKT} leftover" || bad "small disk"
ss=$(sha256sum < "$OUT/s/disk.img" | cut -d' ' -f1)
run "$OUT/s/disk.img" "$OUT/n.txt" "reuse,now" '^installer: \(BESIDE_NO\|done\|ERROR\)' 120
tr -d '\000' < "$OUT/n.txt" | grep -aq '^installer: BESIDE_NO' && ok "install refused" || bad "install not refused"
[ "$(sha256sum < "$OUT/s/disk.img" | cut -d' ' -f1)" = "$ss" ] && ok "disk byte-identical after refusal" || bad "refusal wrote to the disk"

echo "OSUMREUSE: $pass passed, $fail failed"
[ "$fail" = 0 ]
