#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
GRABS=${GRABTEAR_GRABS:-40}
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

guest() {
    local name=$1 words=$2 pid i
    cp -f "$OUT/img/disk.img" "$OUT/$name.img"; : > "$OUT/$name.txt"
    timeout 150 qemu-system-x86_64 -accel kvm -machine pc -cpu Haswell -m 512 -smp 4 -kernel "$OUT/bd/k0.mb" \
        -append "gfx wm wig wigicons wmhold wiglong nokbd nosched noproc nofs r3alle wighalt=300 $words wigapp=/bin/grabtear,run,$GRABS" \
        -serial "file:$OUT/$name.txt" -display none -no-reboot -vga std \
        -drive "file=$OUT/$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
    pid=$!
    i=0
    while [ $i -lt 140 ]; do
        grep -qa 'grabtear: grabs=\|grabtear: grab fail' "$OUT/$name.txt" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 1; i=$((i+1))
    done
    sleep 1; kill "$pid" 2>/dev/null
    rm -f "$OUT/$name.img"
}

field() { grep -a 'grabtear: grabs=' "$OUT/$1.txt" | head -1 | sed -n "s/.* $2=\([0-9]*\).*/\1/p"; }

echo "== build =="
ALLTAGBUILD="$OUT/bd" OSUM_SMP=4 bash tools/alltag/build.sh "$OUT/img" desk=no accel=kvm shot=no warten=0 \
    extra="r3alle wighalt=5 wigapp=/bin/grabtear,run,2" progs="grabtear sh echo ls cat" > "$OUT/build.log" 2>&1
[ -s "$OUT/bd/k0.mb" ] && [ -s "$OUT/img/disk.img" ] && ok "image built" || { bad "image build"; tail -5 "$OUT/build.log"; }

echo "== 1. snapshot grab: every frame is one painted colour =="
guest snap ""
G=$(field snap grabs); M=$(field snap mixed); A=$(field snap a); B=$(field snap b)
[ "${G:-0}" -eq "$GRABS" ] && ok "all $GRABS grabs finished" || bad "grabs finished: ${G:-none} of $GRABS"
[ "${M:-1}" -eq 0 ] && ok "no mixed frame (mixed=0)" || bad "mixed frames: ${M:-none}"
[ $(( ${A:-0} + ${B:-0} )) -ge 5 ] && ok "the painter was visible (a=$A b=$B)" || bad "painter not seen (a=${A:-none} b=${B:-none})"

echo "== 2. counter-proof: noshotsnap tears =="
guest live "noshotsnap"
M2=$(field live mixed); A2=$(field live a); B2=$(field live b)
[ "${M2:-0}" -ge 1 ] && ok "without the snapshot frames tear (mixed=$M2, a=$A2 b=$B2)" || bad "no tear without snapshot (mixed=${M2:-none}) -- the test cannot fail"

echo
echo "GRABTEAR: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
