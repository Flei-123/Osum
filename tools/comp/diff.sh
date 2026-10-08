#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/comp/diff.sh -- THE COMPOSITING LIBRARY EQUALS THE OLD ROW LOOPS (docs/COMPOSITOR.md stage S2).
#
#   bash tools/comp/diff.sh        (start it through /root/jarvis/bin/heavy)
#
# Boots the kernel with `/bin/compdiff` (kernel/user/compdiff.fi): frozen copies of the old window-server loops (`fb_row`,
# `fb_row_mix`, `blend`, `blur_line`) against `lib/fui/comp.fi` on random input, whole buffers (guard words included) compared
# octet for octet, plus every one of the 16.7 million (alpha, src, dst) triples of `mix8`. Every line `compdiff: <name> <cases> <differences>`
# must have 0 differences and a case count.
set -uo pipefail
cd "$(dirname "$0")/../.."
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

PROGS="compdiff sh echo"
bash tools/build-kernel.sh "$D/k0.mb" > "$D/k0.log" 2>&1 || { bad "the kernel does not build"; tail -5 "$D/k0.log"; echo "COMPDIFF: $pass passed, $fail failed"; exit 1; }
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/bin.log" 2>&1 && ok "the kernel and $(echo $PROGS | wc -w) programs build" \
    || { bad "programs do not build"; head -10 "$D/bin.log"; echo "COMPDIFF: $pass passed, $fail failed"; exit 1; }
MK=""
for p in $PROGS; do MK="$MK /bin/$p=$D/bin/$p.elf"; done
python3 tools/osum/mkfs.py build "$D/root.img" 4096 /bin/ /dev/ /mnt/ $MK > "$D/mkfs.log" 2>&1 || { bad "mkfs"; cat "$D/mkfs.log"; exit 1; }

mkdir -p "$D/vm"; cp "$D/root.img" "$D/vm/hda.img"
timeout 600 qemu-system-x86_64 -accel kvm -kernel "$D/k0.mb" -m 512 -smp 1 \
    -append "osum nokbd vfs nopart script=compdiff;exit" \
    -serial "file:$D/vm/serial.txt" -display none -no-reboot \
    -drive "file=$D/vm/hda.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
S="$D/vm/serial.txt"
grep -a '^compdiff:' "$S" | sed 's/^/        /'
grep -aq '^compdiff: done' "$S" && ok "the program ran to the end" || { bad "no 'compdiff: done'"; tail -40 "$S" | sed 's/^/        | /'; }
for name in box_recip mix8 blend copy_row mix_row blur_line; do
    line=$(grep -a "^compdiff: $name " "$S" | tail -1)
    cases=$(echo "$line" | awk '{print $3}'); diffs=$(echo "$line" | awk '{print $4}')
    if [ -z "$line" ]; then bad "$name: no result line"
    elif [ "${cases:-0}" -gt 0 ] && [ "${diffs:-1}" = 0 ]; then ok "$name: $cases cases, 0 differences"
    else bad "$name: $cases cases, $diffs differences"; fi
done

echo
echo "COMPDIFF: $pass passed, $fail failed"
[ "$fail" = 0 ]
