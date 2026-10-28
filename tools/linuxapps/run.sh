#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/linuxapps/run.sh -- boot a REAL Linux application stack (an Alpine root with e.g. Firefox) in Osum under QEMU and record where it fails.
#
#   bash tools/linuxapps/prep-firefox.sh <workdir>            # once: Alpine root + `apk add firefox` + Linux strace reference (needs net, bwrap)
#   /root/jarvis/bin/heavy bash tools/linuxapps/run.sh <workdir> <guest-script> [outdir]
#
# <guest-script> is run by Alpine's busybox init as the sysinit line (/etc/fx.sh); everything it prints goes to the serial log.
# Env: KERNEL=<k0.img|osum.mb> (default: builds stufe 0), MEM (MiB, 3072), TMO (s, 600), BLOCKS (512-byte blocks, 900000), DRIVE (ide|ahci),
#      KARGS (default "osum vfs nokbd nosched noproc nofs fremdtrace"), SMP (1), DONE (marker the guest prints at the end, FX-END),
#      SPEC (an existing mkroot spec; default <workdir>/fxrun/spec.txt), KEEP=1 (keep the disk image),
#      GUI=1 (replace busybox sh/sleep/echo/cat/ls by the Osum programs, add wayd, fonts and keymaps: the guest script is then an Osum-sh script),
#      EXTRA="/guest/path=host/path@755 ..." (more spec entries).
# Result: <outdir>/ser.txt (raw serial), <outdir>/ser.clean, <outdir>/summary.txt (ENOSYS numbers, failing mem calls, user faults, guest markers).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
WD=${1:?workdir}; GS=${2:?guest script}; OUT=${3:-$WD/out-$(date +%H%M%S)}
mkdir -p "$OUT"
SPEC=${SPEC:-$WD/fxrun/spec.txt}
[ -r "$SPEC" ] || { echo "LINUXAPPS: no spec $SPEC (run prep-firefox.sh)"; exit 1; }
KARGS=${KARGS:-osum vfs nokbd nosched noproc nofs fremdtrace}
MEM=${MEM:-3072}; TMO=${TMO:-600}; BLOCKS=${BLOCKS:-900000}; DONE=${DONE:-FX-END}; DRIVE=${DRIVE:-ide}
ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
if [ -z "${KERNEL:-}" ]; then
    bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
    ./tools/build-kernel.sh "$OUT/k0.img" --stufe 0 > "$OUT/kernel.log" 2>&1 || { echo "LINUXAPPS: kernel build failed"; tail -5 "$OUT/kernel.log"; exit 1; }
    KERNEL=$OUT/k0.img
fi
cp "$GS" "$OUT/fx.sh"
printf '::sysinit:/bin/sh /etc/fx.sh\n::shutdown:/bin/true\n' > "$OUT/inittab"
# the spec comes from the Alpine root; replace its inittab and add the guest script
grep -v '^/etc/inittab' "$SPEC" > "$OUT/spec.txt"
if [ -n "${GUI:-}" ]; then
    GUI_PROGS="sh sleep echo cat ls wayd ${GUI_EXTRA:-}"
    mkdir -p "$OUT/bin" "$OUT/km"
    bash tools/sync/build.sh "$OUT/bin" 0 $GUI_PROGS > "$OUT/progs.log" 2>&1 || { echo "LINUXAPPS: gui programs failed"; tail -5 "$OUT/progs.log"; exit 1; }
    python3 tools/wayland/genkeys.py --keymaps "$OUT/km" > "$OUT/keys.log" 2>&1 || { echo "LINUXAPPS: keymaps failed"; tail -5 "$OUT/keys.log"; exit 1; }
    grep -v -E "^/bin/($(echo $GUI_PROGS | tr ' ' '|'))(=|->)" "$OUT/spec.txt" > "$OUT/spec.gui" && mv "$OUT/spec.gui" "$OUT/spec.txt"
    for p in $GUI_PROGS; do echo "/bin/$p=$OUT/bin/$p.elf@755" >> "$OUT/spec.txt"; done
    for d in /lib/ /usr/share/wayd/; do grep -qxF "$d@755" "$OUT/spec.txt" || echo "$d@755" >> "$OUT/spec.txt"; done
    {
        echo "/lib/mono.ttf=assets/osum-mono.ttf"; echo "/lib/sans.ttf=assets/osum-sans.ttf"
        [ -f assets/osum-icons.ttf ] && echo "/lib/icons.ttf=assets/osum-icons.ttf"
        [ -f assets/osum-sans-bold.ttf ] && echo "/lib/bold.ttf=assets/osum-sans-bold.ttf"
        echo "/usr/share/wayd/keymap-us.xkb=$OUT/km/keymap-us.xkb"; echo "/usr/share/wayd/keymap-de.xkb=$OUT/km/keymap-de.xkb"
    } >> "$OUT/spec.txt"
fi
if [ -f "$WD/fx-root/usr/share/mime/mime.cache" ]; then
    grep -qxF "/usr/share/mime/@755" "$OUT/spec.txt" || { grep -qxF "/usr/share/@755" "$OUT/spec.txt" || echo "/usr/share/@755" >> "$OUT/spec.txt"; echo "/usr/share/mime/@755" >> "$OUT/spec.txt"; }
    grep -q "^/usr/share/mime/mime.cache=" "$OUT/spec.txt" || echo "/usr/share/mime/mime.cache=$WD/fx-root/usr/share/mime/mime.cache@644" >> "$OUT/spec.txt"
fi
for e in ${EXTRA:-}; do echo "$e" >> "$OUT/spec.txt"; done
mapfile -t SP < "$OUT/spec.txt"
python3 tools/osum/mkfs.py build "$OUT/disk.img" "$BLOCKS" --v3 --inodes=${INODES:-4096} "${SP[@]}" "/etc/fx.sh=$OUT/fx.sh@755" "/etc/inittab=$OUT/inittab" > "$OUT/mkfs.log" 2>&1 \
    || { echo "LINUXAPPS: mkfs failed"; tail -5 "$OUT/mkfs.log"; exit 1; }
echo "LINUXAPPS: disk $(stat -c%s "$OUT/disk.img") bytes, kernel $KERNEL"
DRV=(-drive "file=$OUT/disk.img,format=raw,if=ide,index=0")
[ "$DRIVE" = ahci ] && DRV=(-device ahci,id=ahci -drive "file=$OUT/disk.img,format=raw,if=none,id=d0" -device ide-hd,drive=d0,bus=ahci.0)
SOCK="$OUT/mon.sock"; rm -f "$SOCK"
timeout "$TMO" qemu-system-x86_64 "${ACC[@]}" -smp "${SMP:-1}" -kernel "$KERNEL" -m "$MEM" -append "$KARGS" \
    -serial "file:$OUT/ser.txt" -display none -no-reboot -monitor "unix:$SOCK,server,nowait" "${DRV[@]}" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$OUT/qemu.txt" 2>&1 &
QPID=$!
i=0
while kill -0 "$QPID" 2>/dev/null; do
    grep -qaF -- "$DONE" "$OUT/ser.txt" 2>/dev/null && break
    sleep 1; i=$((i + 1)); [ "$i" -ge "$TMO" ] && break
done
sleep 2
printf 'quit\n' | socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1
wait "$QPID" 2>/dev/null
tr -cd '\11\12\15\40-\176' < "$OUT/ser.txt" | tr -d '\r' > "$OUT/ser.clean"
{
  echo "== boot lines: $(wc -l < "$OUT/ser.clean"), serial bytes $(stat -c%s "$OUT/ser.txt")"
  echo "== ENOSYS numbers:"; grep -a '^sys: ENOSYS nr' "$OUT/ser.clean" | sort | uniq -c | sort -rn | head -40
  echo "== failing mem/thread calls:"; grep -a '^sys: ERR nr' "$OUT/ser.clean" | awk '{print $3,$4,$5,$6,$7}' | sort | uniq -c | sort -rn | head -20
  echo "== user faults:"; grep -a 'user fault' "$OUT/ser.clean" | head -10
  echo "== guest markers:"; grep -a '^FX' "$OUT/ser.clean" | head -80
} > "$OUT/summary.txt"
cat "$OUT/summary.txt"
[ -n "${KEEP:-}" ] || rm -f "$OUT/disk.img"
echo "LINUXAPPS: done (out $OUT)"
