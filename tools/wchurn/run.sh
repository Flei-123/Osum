#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wchurn/run.sh -- r1138: THE WINDOW SERVER IS SAFE ON SEVERAL CORES.
#
#   bash tools/wchurn/run.sh [rounds]
#
# Before: ring 3 window calls (WM_CREATE, WM_FILL, WM_FLUSH, WM_CLOSE ...) ran
# on every core at the same time with NO lock around the window tables and the
# compositor (kernel/ui/wm.fi). Measured here: on -smp 4 a freshly made window
# answered WM_INFO with 0x0 or refused WM_FILL / WM_FLUSH in 5-20 % of the
# runs' windows (`wchurn: wN ... bad=`). The kernel #GP of r1138 (RIP in the
# kernel stack, core 2, desktop, sys_wm -> wm_call) is the same family.
# After: `atomic.L_GUI` around `gfx.sys_wm` / `gfx.sys_wig`.
#
# The guest `wchurn run 8 60 6`: 8 workers create / paint / flush / close
# windows, the parent kills half of them mid-run and starts new ones, 6 rounds.
#   1. tree as it is           -> `wchurn: done ... bad=0` in every round
#   2. copy WITHOUT the lock   -> bad > 0 in at least one round (the test can fail)
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
ROUNDS=${1:-3}
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
ARGS=${WCHURN_ARGS:-8,60,6}

guest() { # guest <name> <kernel> <disk>
    local n=$1 k=$2 disk=$3 pid i
    cp -f "$disk" "$OUT/$n.img"; : > "$OUT/$n.txt"
    timeout 120 qemu-system-x86_64 -accel kvm -machine pc -cpu Haswell -m 512 -smp 4 -kernel "$k" \
        -append "gfx wm wig wigicons wmhold wiglong nokbd nosched noproc nofs r3alle wighalt=300 wigapp=/bin/wchurn,run,$ARGS" \
        -serial "file:$OUT/$n.txt" -display none -no-reboot -vga std \
        -drive "file=$OUT/$n.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
    pid=$!
    i=0
    while [ $i -lt 110 ]; do
        grep -qa 'wchurn: done' "$OUT/$n.txt" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 1; i=$((i+1))
    done
    sleep 1; kill "$pid" 2>/dev/null
    rm -f "$OUT/$n.img"
}

build() { # build <tree> <name>
    (cd "$1" && ALLTAGBUILD="$OUT/bd-$2" OSUM_SMP=4 bash tools/alltag/build.sh "$OUT/$2" desk=no accel=kvm shot=no warten=0 \
        extra="r3alle wighalt=5 wigapp=/bin/wchurn,run,2,2,0" progs="wchurn sh echo ls cat" > "$OUT/$2.log" 2>&1)
    [ -s "$OUT/bd-$2/k0.mb" ] && [ -s "$OUT/$2/disk.img" ]
}

echo "== build: tree as it is, and a copy without the window lock =="
build "$ROOT" cur && ok "tree built" || bad "tree build"
rm -rf "$OUT/revtree"; mkdir -p "$OUT/revtree"
tar --exclude=.git --exclude='*.o' -cf - . | (cd "$OUT/revtree" && tar xf -)
python3 -I - "$OUT/revtree" <<'PY'
import sys, os
f = os.path.join(sys.argv[1], "kernel/gfx/gfx.fi")
s = open(f).read()
n = s.count("atomic.lock_take(state, atomic.L_GUI, cpu.here(state))")
s = s.replace("    atomic.lock_take(state, atomic.L_GUI, cpu.here(state))\n", "").replace("    atomic.lock_give(state, atomic.L_GUI)\n", "")
open(f, "w").write(s)
print(n)
PY
build "$OUT/revtree" rev && ok "copy without lock built" || bad "copy build"

echo "== 1. with the lock: $ROUNDS rounds, 4 cores =="
good=0
for r in $(seq 1 "$ROUNDS"); do
    guest "c$r" "$OUT/bd-cur/k0.mb" "$OUT/cur/disk.img"
    line=$(grep -ao 'wchurn: done w=[0-9]* bad=[0-9]* kills=[0-9]*' "$OUT/c$r.txt" | tail -1)
    if [ -n "$line" ] && echo "$line" | grep -q 'bad=0 '; then good=$((good+1)); else echo "        round $r: ${line:-no 'done' line}"; fi
done
[ "$good" = "$ROUNDS" ] && ok "every round done with bad=0 ($good/$ROUNDS)" || bad "rounds clean: $good/$ROUNDS"
grep -aq 'KERNSTAPEL\|user fault\|general protection\|PANIC' "$OUT"/c*.txt && bad "kernel complaint in the serial log" || ok "no kernel fault lines"

echo "== 2. NEGATIVE CONTROL: without the lock the windows go wrong =="
red=0
for r in $(seq 1 "$ROUNDS"); do
    guest "r$r" "$OUT/bd-rev/k0.mb" "$OUT/rev/disk.img"
    line=$(grep -ao 'wchurn: done w=[0-9]* bad=[0-9]* kills=[0-9]*' "$OUT/r$r.txt" | tail -1)
    if [ -z "$line" ] || ! echo "$line" | grep -q 'bad=0 '; then red=$((red+1)); fi
done
[ "$red" -ge 1 ] && ok "without the lock $red of $ROUNDS rounds are bad or dead" || bad "the copy without the lock stayed clean: the test would not catch the race"

echo "wchurn: $pass/$fail OK/FAIL"
[ "$fail" = 0 ]
