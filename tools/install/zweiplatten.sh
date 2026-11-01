#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
export BOOT_KERNEL_COPY=1   # r1223: QEMU -kernel/-initrd has no boot medium; the installer needs /boot/osum.mb in the root
. tools/lib/qemu.sh

BAU=${1:-/tmp/abnahme/bau}
OUT=${2:-/tmp/zweiplatten}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/lock.sh" && osum_sperre "$OUT"   # A-024
mkdir -p "$OUT"

ok=0; bad=0
ok()  { printf '  [ ok ] %s\n' "$*"; ok=$((ok+1)); }
bad() { printf '  [FEHL] %s\n' "$*"; bad=$((bad+1)); }

[ -f "$BAU/osum.mb" ] || { echo "== $BAU/osum.mb fehlt -- erst tools/install/acceptance.sh laufen lassen" >&2; exit 1; }
[ -f "$BAU/root.img" ] || { echo "== $BAU/root.img fehlt" >&2; exit 1; }

QUELLE=${QUELLE:-/tmp/abnahme/platte.img}
if [ ! -f "$QUELLE" ]; then
    echo "== $QUELLE fehlt -- erst tools/install/acceptance.sh laufen lassen" >&2
    exit 1
fi
cp -f "$QUELLE" "$OUT/hda.img"
VORHER=$(sha256sum < "$OUT/hda.img" | cut -d' ' -f1)
echo "   hda  eine fertige Installation, sha256 ${VORHER:0:16}…"

rm -f "$OUT/hdb.img"
head -c $((320 * 1024 * 1024)) /dev/zero > "$OUT/hdb.img"
echo "   hdb  empty, 320 MiB -- the target"

APPEND="modfs osum vfs gfx wm wig wmhold wmdauer wighalt=1200 nokbd nosched noproc nofs"
APPEND="$APPEND lang=de uiscale=1 wigapp=/bin/installer,now,second"

timeout "${LIMIT:-1200}" $QEMU_X86 -m 512 \
    -kernel "$BAU/osum.mb" -initrd "$BAU/root.img" -append "$APPEND" \
    -serial "file:$OUT/ser.txt" -display none -no-reboot \
    -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
    -drive "file=$OUT/hda.img,format=raw,if=ide,index=0" \
    -drive "file=$OUT/hdb.img,format=raw,if=ide,index=1" > "$OUT/qemu.log" 2>&1 &
QP=$!
i=0
while [ $i -lt 1200 ]; do
    grep -qa 'installer: done\|installer: ERROR' "$OUT/ser.txt" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 1; i=$((i+1))
done
sleep 4
kill "$QP" 2>/dev/null
wait "$QP" 2>/dev/null

echo
echo "== what the program saw and did"
grep -aE '^installer: (disk|ready|gewaehlt|esp=|fertig|FEHLER|bei=)' "$OUT/ser.txt" \
    | head -12 | sed 's/^/        /'
echo

n=$(grep -aoE 'installer: ready n=[0-9]+' "$OUT/ser.txt" | head -1 | sed 's/.*=//')
[ "${n:-0}" -ge 2 ] && ok "both disks in the list (n=$n)" \
    || bad "only ${n:-0} disk(s) found -- the attempt measures nothing"

esp=$(grep -aoE 'installer: esp=/dev/[a-z0-9]+' "$OUT/ser.txt" | head -1 | sed 's/.*esp=//')
if [ "$esp" = "/dev/hdb1" ]; then
    ok "it mounted the EFI partition of the TARGET: $esp"
elif [ "$esp" = "/dev/hda1" ]; then
    bad "it mounted /dev/hda1 -- i.e. the FOREIGN disk"
else
    bad "no or unknown EFI partition: '${esp:-keine}'"
fi

grep -qa 'installer: done' "$OUT/ser.txt" \
    && ok "the installation reports done" \
    || bad "the installation did not finish"

NACHHER=$(sha256sum < "$OUT/hda.img" | cut -d' ' -f1)
if [ "$VORHER" = "$NACHHER" ]; then
    ok "THE FIRST DISK IS UNCHANGED OCTET FOR OCTET"
else
    bad "the first disk was written -- ${VORHER:0:16}… -> ${NACHHER:0:16}…"
fi

sgdisk -p "$OUT/hdb.img" > "$OUT/hdb-gpt.txt" 2>&1
grep -q 'EF00' "$OUT/hdb-gpt.txt" && ok "the second disk has an EFI partition" \
    || bad "there is no EFI partition on the second disk"
grep -qE 'OSUM' "$OUT/hdb-gpt.txt" && ok "the second disk has a root partition" \
    || bad "there is no root partition on the second disk"
if mdir -i "$OUT/hdb.img@@1048576" ::/EFI/BOOT 2>/dev/null | grep -qi 'BOOTX64'; then
    ok "the boot loader is on the EFI partition of the SECOND disk"
else
    bad "no boot loader on the second disk"
fi

printf '\n=======================================================\n'
printf 'ZWEI PLATTEN:  %d gruen, %d rot\n' "$ok" "$bad"
printf '=======================================================\n'
[ "$bad" = 0 ] || exit 1
exit 0
