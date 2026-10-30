#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
PROGS="sh cat echo ls rm"
FILE_KIB=${BU_KIB:-8192}
IOPS=${BU_IOPS:-1000}
HARD=${BU_HARD:-3}
EXPECT=${BU_EXPECT:-quiet}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || exit 1
K=${1:-}
if [ -z "$K" ]; then
    bash tools/build-kernel.sh "$W/k0.mb" --stufe 0 > "$W/build.log" 2>&1 || { tail -15 "$W/build.log"; exit 1; }
    K="$W/k0.mb"
fi
as --64 -o "$W/crt.o" kernel/user/crt.s
MKARGS=""
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$W/$p.o" > "$W/e$p" 2>&1 || { echo "firnc $p"; head -5 "$W/e$p"; exit 1; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" -o "$W/$p.elf" "$W/crt.o" "$W/$p.o" || exit 1
    strip --strip-all "$W/$p.elf"
    MKARGS="$MKARGS /bin/$p=$W/$p.elf"
done
head -c "$((FILE_KIB * 1024))" /dev/urandom > "$W/big.bin"
printf 'keep\n' > "$W/keep.txt"
cat > "$W/s.sh" <<'SEOF'
echo @@start
cat /proc/uptime
rm /t/big.bin
echo "@@rm-rc=$?"
cat /proc/uptime
ls /t
echo @@end
SEOF
BLOCKS=$(( FILE_KIB * 2 + 30000 ))
python3 tools/osum/mkfs.py build "$W/root.img" "$BLOCKS" /bin/ /proc/ /dev/ /t/ $MKARGS \
    "/t/s.sh=$W/s.sh" "/t/big.bin=$W/big.bin" "/t/keep.txt=$W/keep.txt" > "$W/mkfs.log" 2>&1 || { tail -3 "$W/mkfs.log"; exit 1; }
ACC=""; [ "$OSUM_QEMU_ACCEL" = kvm ] && ACC="-cpu host"
timeout ${BU_TIMEOUT:-900} $QEMU_X86 $ACC -kernel "$K" -m 512 \
    -append "osum nokbd vfs nmihard=$HARD noreset script=sh /t/s.sh;exit" \
    -serial "file:$W/out.txt" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -drive "file=$W/root.img,format=raw,if=ide,index=0,throttling.iops-total=$IOPS" >/dev/null 2>&1
rc=$?
tr -d '\r\000' < "$W/out.txt" > "$W/clean.txt"
[ -n "${BU_SHOW:-}" ] && sed -n "/@@start/,/@@end/p" "$W/clean.txt"
UPS=$(sed -n '/@@start/,/@@end/p' "$W/clean.txt" | grep -aE '^[0-9]+(\.[0-9]+)?( |$)' | awk '{print $1}')
T0=$(echo "$UPS" | sed -n 1p); T1=$(echo "$UPS" | sed -n 2p)
SECS=$(awk -v a="${T0:-0}" -v b="${T1:-0}" 'BEGIN{printf "%.2f", b-a}')
echo "BIGUNLINK: file ${FILE_KIB} KiB at ${IOPS} IOPS, rm took ${SECS} s (hard limit ${HARD} s)"
if [ "$EXPECT" != hang ]; then
    [ "$rc" = 21 ] && ok "OS finished (rc 21)" || bad "OS rc=$rc"
    grep -aq '@@rm-rc=0' "$W/clean.txt" && ok "rm of the big file succeeded" || bad "rm failed"
    grep -aq 'keep.txt' "$W/clean.txt" && ok "other file still listed" || bad "other file missing"
fi
if grep -aq 'hang: cpu' "$W/clean.txt"; then
    grep -a -m3 'hang:' "$W/clean.txt" | cut -c1-160 | sed 's/^/    /'
    [ "$EXPECT" = hang ] && ok "freeze logger fired (expected on the old kernel)" || bad "freeze logger fired during rm"
else
    [ "$EXPECT" = hang ] && bad "freeze logger silent (expected a report)" || ok "no freeze logger report"
fi
echo "BIGUNLINK: $pass ok, $fail failed"
[ "$fail" = 0 ]
