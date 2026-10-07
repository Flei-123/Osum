#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/comp/run.sh -- WHAT DOES COMPOSITING COST IN RING 3? (docs/COMPOSITOR.md section 5, points 2 and 3)
#
#   bash tools/comp/run.sh        (start it through /root/jarvis/bin/heavy)
#
# Boots the kernel with `/bin/compbench` (kernel/user/compbench.fi): the window server's primitives written in Firn and run in a
# user program (row copy, per-pixel blend, box blur), and a pipe ping-pong between two processes (the wake-up of the compositor).
# Runs with 1 and with 4 cores. The numbers are printed, and checked against the budget of a 60 Hz frame: the whole point is
# whether a ring-3 compositor can hold <= 16 ms.
set -uo pipefail
cd "$(dirname "$0")/../.."
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

PROGS="compbench sh echo"
bash tools/build-kernel.sh "$D/k0.mb" > "$D/k0.log" 2>&1 || { bad "the kernel does not build"; tail -5 "$D/k0.log"; echo "COMP: $pass passed, $fail failed"; exit 1; }
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/bin.log" 2>&1 && ok "the kernel and $(echo $PROGS | wc -w) programs build" \
    || { bad "programs do not build"; head -10 "$D/bin.log"; echo "COMP: $pass passed, $fail failed"; exit 1; }
MK=""
for p in $PROGS; do MK="$MK /bin/$p=$D/bin/$p.elf"; done
python3 tools/osum/mkfs.py build "$D/root.img" 4096 /bin/ /dev/ /mnt/ $MK > "$D/mkfs.log" 2>&1 || { bad "mkfs"; cat "$D/mkfs.log"; exit 1; }

for smp in 1 4; do
    echo "== ring-3 compositing primitives, $smp core(s) =="
    mkdir -p "$D/vm$smp"; cp "$D/root.img" "$D/vm$smp/hda.img"
    timeout 240 qemu-system-x86_64 -accel kvm -kernel "$D/k0.mb" -m 512 -smp $smp \
        -append "osum nokbd vfs nopart script=compbench;exit" \
        -serial "file:$D/vm$smp/serial.txt" -display none -no-reboot \
        -drive "file=$D/vm$smp/hda.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    S="$D/vm$smp/serial.txt"
    grep -a '^compbench:' "$S" | sed 's/^/        /'
    grep -aq '^compbench: done' "$S" && ok "$smp core(s): the program ran to the end" || { bad "$smp core(s): no 'compbench: done'"; continue; }
    num() { grep -a "^compbench: $1 " "$S" | tail -1 | awk '{print $3}'; }
    FULL=$(num full-copy); SMALL=$(num small-copy); MIX=$(num mix-640); BLUR=$(num blur-320x520); PING=$(num roundtrip)
    [ "${FULL:-99999}" -lt 16000 ] && ok "$smp: a whole recompose in ring 3 costs ${FULL} us (budget 16000)" || bad "$smp: full recompose ${FULL:-?} us"
    [ "${SMALL:-99999}" -lt 2000 ] && ok "$smp: a 100 x 100 damage costs ${SMALL} us" || bad "$smp: small damage ${SMALL:-?} us"
    [ "${MIX:-99999}" -lt 16000 ] && ok "$smp: a translucent 640 x 400 window costs ${MIX} us" || bad "$smp: mix ${MIX:-?} us"
    [ "${BLUR:-99999}" -lt 16000 ] && ok "$smp: one blur pass over 320 x 520 costs ${BLUR} us" || bad "$smp: blur ${BLUR:-?} us"
    [ "${PING:-99999}" -lt 2000 ] && ok "$smp: a pipe round trip between two processes costs ${PING} us (the hop of the plan)" || bad "$smp: round trip ${PING:-?} us"
done

echo
echo "COMP: $pass passed, $fail failed"
[ "$fail" = 0 ]
