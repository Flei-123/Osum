#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/gptview/run.sh -- installer "beside" tab on a Windows-laptop-like disk (GPT: ESP, MSR, NTFS, Recovery, no free gap):
# the partition list, the free-space line and the ESP line must be shown (old build: "partition table damaged, 0/0").
# Run under heavy: /root/jarvis/bin/heavy bash tools/gptview/run.sh   (BAU=<usbimg build dir> reuses a build)
set -uo pipefail
cd "$(dirname "$0")/../.."
export BOOT_KERNEL_COPY=1
. tools/lib/qemu.sh
for t in sgdisk mkntfs ntfscp mkfs.vfat python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "GPTVIEW: $t missing"; exit 1; }
done
OUT=$(mktemp -d); QP=""
trap 'kill $QP 2>/dev/null; rm -rf "$OUT"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

build() {
    mkdir -p "$2"
    ( cd "$1" && bash tools/usbimg/build.sh "$2" > "$2.log" 2>&1 )
}

view() {
    local bau=$1 disk=$2 ser=$3
    rm -f "$ser"; : > "$ser"
    timeout 600 $QEMU_X86 -m 512 -kernel "$bau/osum.mb" -initrd "$bau/root.img" \
        -append "modfs osum vfs gfx wm wig wmdauer nosched noproc nofs lang=de uiscale=1 wigapp=/bin/installer,beside" \
        -serial "file:$ser" -display none -no-reboot \
        -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
        -drive "file=$disk,format=raw,if=ide,index=0" > "$ser.qemu" 2>&1 &
    QP=$!
    local i=0
    while [ $i -lt 480 ]; do
        tr -d '\000' < "$ser" 2>/dev/null | grep -aq '^installer: view esp=' && break
        kill -0 "$QP" 2>/dev/null || break
        sleep 0.5; i=$((i + 1))
    done
    sleep 1
    kill $QP 2>/dev/null; wait $QP 2>/dev/null; QP=""
}

field() { tr -d '\000' < "$1" | grep -a "^installer: view $2=" | tail -n 1 | sed "s/^installer: view $2=//"; }

BAU=${BAU:-}
if [ -z "$BAU" ]; then
    BAU="$OUT/bau"
    build "$PWD" "$BAU" || { echo "build failed"; tail -n 5 "$BAU.log"; exit 1; }
fi
[ -f "$BAU/osum.mb" ] && ok "fixed image built" || { bad "fixed image"; echo "GPTVIEW: $pass passed, $fail failed"; exit 1; }

mkdir -p "$OUT/d0" "$OUT/d1"
bash tools/gptview/mkdisk.sh "$OUT/d0" 0 && ok "laptop-like disk without free gap (ESP, MSR, NTFS, Recovery)" || { bad "disk d0"; echo "GPTVIEW: $pass passed, $fail failed"; exit 1; }
bash tools/gptview/mkdisk.sh "$OUT/d1" 40 && ok "same layout with 40 MiB free behind" || { bad "disk d1"; echo "GPTVIEW: $pass passed, $fail failed"; exit 1; }
sum0=$(sha256sum < "$OUT/d0/disk.img" | cut -d' ' -f1)

echo "== 1. no free gap: shrink route =="
view "$BAU" "$OUT/d0/disk.img" "$OUT/s0.txt"
rows=$(field "$OUT/s0.txt" rows); free=$(field "$OUT/s0.txt" free); esp=$(field "$OUT/s0.txt" esp)
printf '        rows=%s\n        free=%s\n        esp=%s\n' "$rows" "$free" "$esp"
[ "$rows" = 4 ] && ok "partition list shows 4 rows" || bad "partition list rows=$rows"
case "$free" in "Kein ausreichend freier Platz auf dieser Platte."*) ok "free line names the missing space" ;; *) bad "free line: $free" ;; esac
case "$free$esp" in *besch*digt*|*"nicht lesbar"*|*"Gelesen/erwartet"*) bad "table reported damaged on a healthy disk" ;; *) ok "no damaged-table text" ;; esac
case "$esp" in "Vorhandene EFI-Partition wird mitbenutzt:"*) ok "ESP line: existing ESP will be shared" ;; *) bad "ESP line: $esp" ;; esac
[ "$(sha256sum < "$OUT/d0/disk.img" | cut -d' ' -f1)" = "$sum0" ] && ok "disk byte-identical after viewing" || bad "disk changed while viewing"

echo "== 2. free gap behind: direct route =="
view "$BAU" "$OUT/d1/disk.img" "$OUT/s1.txt"
rows=$(field "$OUT/s1.txt" rows); free=$(field "$OUT/s1.txt" free); esp=$(field "$OUT/s1.txt" esp)
printf '        rows=%s\n        free=%s\n        esp=%s\n' "$rows" "$free" "$esp"
[ "$rows" = 4 ] && ok "gap disk: 4 rows" || bad "gap disk rows=$rows"
case "$free" in "Freier Platz:"*) ok "gap disk: free space shown" ;; *) bad "gap disk free line: $free" ;; esac
case "$esp" in "Vorhandene EFI-Partition wird mitbenutzt:"*) ok "gap disk: ESP line" ;; *) bad "gap disk ESP line: $esp" ;; esac

echo "== 2b. HP layout (ESP named Basic data partition, MSR, BitLocker C:, recovery) =="
mkdir -p "$OUT/h0" "$OUT/h1"
bash tools/gptview/mkhp.sh "$OUT/h0" 0 && ok "HP-like disk without free gap" || { bad "disk h0"; echo "GPTVIEW: $pass passed, $fail failed"; exit 1; }
bash tools/gptview/mkhp.sh "$OUT/h1" 64 && ok "HP-like disk with 64 MiB free behind" || { bad "disk h1"; echo "GPTVIEW: $pass passed, $fail failed"; exit 1; }
hsum=$(sha256sum < "$OUT/h0/disk.img" | cut -d' ' -f1)
view "$BAU" "$OUT/h0/disk.img" "$OUT/sh0.txt"
rows=$(field "$OUT/sh0.txt" rows); free=$(field "$OUT/sh0.txt" free); esp=$(field "$OUT/sh0.txt" esp)
stat=$(field "$OUT/sh0.txt" stat); beside=$(field "$OUT/sh0.txt" beside); art=$(field "$OUT/sh0.txt" art)
printf '        rows=%s\n        art=%s\n        free=%s\n        stat=%s\n        esp=%s\n        beside=%s\n' "$rows" "$art" "$free" "$stat" "$esp" "$beside"
[ "$rows" = 4 ] && ok "HP: all 4 partitions listed" || bad "HP rows=$rows"
[ "$art" = "EFI-System;MS-reserviert;BitLocker;Wiederherstellung;" ] && ok "HP: type names EFI / MSR / BitLocker / Recovery" || bad "HP art=$art"
case "$stat" in "BitLocker ist aktiv: In Windows (Datentr"*"C: verkleinern"*) ok "HP: BitLocker line names the Disk Management way" ;; *) bad "HP hint line: $stat" ;; esac
case "$free" in "Kein ausreichend freier Platz auf dieser Platte. Frei gefunden: "[01]" MiB, nötig mindestens: 32 MiB") ok "HP: found/needed sizes shown" ;; *) bad "HP free line: $free" ;; esac
case "$esp" in "Vorhandene EFI-Partition wird mitbenutzt:"*) ok "HP: ESP is found despite refused shrink" ;; *) bad "HP ESP line: $esp" ;; esac
case "$free$esp" in *"Keine EFI-Systempartition"*) bad "HP: false 'no ESP' text" ;; *) ok "HP: no false 'no ESP' text" ;; esac
[ "$beside" = 0 ] && ok "HP: beside stays off without a gap" || bad "HP beside=$beside"
[ "$(sha256sum < "$OUT/h0/disk.img" | cut -d' ' -f1)" = "$hsum" ] && ok "HP disk byte-identical after viewing" || bad "HP disk changed"
view "$BAU" "$OUT/h1/disk.img" "$OUT/sh1.txt"
rows=$(field "$OUT/sh1.txt" rows); free=$(field "$OUT/sh1.txt" free); esp=$(field "$OUT/sh1.txt" esp)
stat=$(field "$OUT/sh1.txt" stat); beside=$(field "$OUT/sh1.txt" beside)
printf '        rows=%s\n        free=%s\n        stat=%s\n        esp=%s\n        beside=%s\n' "$rows" "$free" "$stat" "$esp" "$beside"
[ "$rows" = 4 ] && ok "HP gap: 4 rows" || bad "HP gap rows=$rows"
case "$free" in "Freier Platz: 6"[0-9]" MiB"*) ok "HP gap: free space shown" ;; *) bad "HP gap free line: $free" ;; esac
[ -z "$stat" ] && ok "HP gap: no shortage line" || bad "HP gap stat=$stat"
case "$esp" in "Vorhandene EFI-Partition wird mitbenutzt:"*) ok "HP gap: existing ESP shared" ;; *) bad "HP gap ESP line: $esp" ;; esac
[ "$beside" = 1 ] && ok "HP gap: beside enabled" || bad "HP gap beside=$beside"

echo "== 3. counter-proof: old gpt_pruefen =="
mkdir -p "$OUT/old"
tar --exclude=.git -cf - . | tar -xf - -C "$OUT/old"
python3 -I - "$OUT/old/kernel/user/dualkern.fi" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='latin-1').read()
a = "    return st_gpt_ok == 1\n"
assert a in s
open(p, 'w', encoding='latin-1').write(s.replace(a, "    return st_reason == D_NONE\n", 1))
PY
build "$OUT/old" "$OUT/oldbau" && ok "old image built" || { bad "old image"; tail -n 5 "$OUT/oldbau.log"; }
view "$OUT/oldbau" "$OUT/d0/disk.img" "$OUT/o0.txt"
orows=$(field "$OUT/o0.txt" rows); ofree=$(field "$OUT/o0.txt" free)
printf '        old rows=%s\n        old free=%s\n' "$orows" "$ofree"
[ "$orows" = 0 ] && ok "old build shows 0 rows" || bad "old build rows=$orows"
case "$ofree" in *besch*digt*) ok "old build says the table is damaged (bug reproduced)" ;; *) bad "old build free line: $ofree" ;; esac

echo "GPTVIEW: $pass passed, $fail failed"
[ "$fail" = 0 ]
