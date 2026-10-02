#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fsrobust/r200.sh -- DAILY-DRIVER: THE NEGATIVE CONTROL r200 NEVER HAD.
#
#   bash tools/fsrobust/r200.sh
#
# Roadmap r200 (27.09.2026): "128 octets from byte 16 of a sector zeroed, at
# random" on an installed system. The fix of that day (kstate.BLOCKK_OFF, one
# copy page per core) was never confirmed independently: tools/fsrobust/wrace.sh
# stays green with the fix taken back, because its writers share the file-system
# lock and never meet in the page.
#
# WHAT MEETS IN THE PAGE: kernel/sys/sysgui.fi `wl_fill` zeroes
# `blockb(state)+3600 .. +3727` (WL_BYTES = 128) before it fills in one record
# of the window table -- the taskbar polls that call. 3600 mod 512 = 16: the
# very symptom of r200. A file write bounces its 4 KiB block through the same
# page, OUTSIDE the file-system lock on the window side.
#
# THE TEST: /bin/wrace starts four writers on four cores (-smp 4 r3alle) AND
# /bin/wspam, which does what the taskbar does (a window with a screen edge
# reserved, then WM_LIST in a loop) under the real window server; every octet
# the writers wrote is read back and compared.
#
#   1. the tree as it is        -> `wrace: ok files=4`      (the fix holds)
#   2. a COPY of the tree whose `blockb` gives every caller the one shared page
#      (the state before the fix) -> `wrace: BAD ...`       (the test CAN fail;
#      it names block 0, octet 3600 -- the window-list record)
#   Without 2 a green 1 would prove nothing.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${OUT:-/tmp/r200-run}
mkdir -p "$OUT"
. tools/lib/sperre.sh && osum_sperre "$OUT"
POLLS=${R200_POLLS:-4000}
KIB=${R200_KIB:-128}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# a guest run: name kernel disk
guest() {
    local n=$1 k=$2 disk=$3 pid i
    cp -f "$disk" "$OUT/$n.img"; : > "$OUT/$n.txt"
    timeout 420 qemu-system-x86_64 -accel kvm -machine pc -cpu Haswell -m 512 -smp 4 -kernel "$k" \
        -append "gfx wm wig wigicons wmhold wiglong nokbd nosched noproc nofs r3alle wighalt=300 wigapp=/bin/wrace,run,/w1,4,$KIB,$POLLS" \
        -serial "file:$OUT/$n.txt" -display none -no-reboot -vga std \
        -drive "file=$OUT/$n.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
    pid=$!
    i=0
    while [ $i -lt 400 ]; do
        grep -qaE 'wrace: (ok|FAILED)' "$OUT/$n.txt" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 1; i=$((i+1))
    done
    sleep 1
    kill "$pid" 2>/dev/null; pkill -P "$pid" 2>/dev/null
    rm -f "$OUT/$n.img"
}

echo "== 1. build: the tree as it is, and a copy with the shared copy page =="
mkdir -p "$OUT/bd-cur" "$OUT/bd-rev"
ALLTAGBUILD="$OUT/bd-cur" OSUM_SMP=4 bash tools/alltag/build.sh "$OUT/cur" desk=no accel=kvm shot=no warten=0 \
    extra="r3alle wighalt=5 wigapp=/bin/wrace,run,/w0,1,4,1" progs="wrace wspam sh echo ls cat" > "$OUT/cur.log" 2>&1
[ -s "$OUT/bd-cur/k0.mb" ] && [ -s "$OUT/cur/disk.img" ] && ok "kernel and disk of the tree built" \
    || { bad "build of the tree"; tail -5 "$OUT/cur.log"; }
rm -rf "$OUT/revtree"; mkdir -p "$OUT/revtree"
tar --exclude=.git --exclude='*.o' -cf - . | (cd "$OUT/revtree" && tar xf -)
python3 - "$OUT/revtree" <<'PY'
import sys, os
root = sys.argv[1]
for p in ("kernel/sys/sys.fi", "kernel/sys/sysgui.fi"):
    f = os.path.join(root, p)
    s = open(f).read()
    i = s.index("fn blockb(state: u64) -> u64 {")
    j = s.index("\n}\n", i) + 3
    s = s[:i] + "fn blockb(state: u64) -> u64 {\n    // NEGATIVE CONTROL (r200): the state before the fix -- one shared page\n    return state + kstate.BLOCK_OFF\n}\n" + s[j:]
    open(f, "w").write(s)
PY
n=$(diff -rq kernel "$OUT/revtree/kernel" 2>/dev/null | wc -l)
[ "$n" = 2 ] && ok "the copy differs from the tree in exactly two files (the two blockb)" || bad "the copy differs in $n files"
(cd "$OUT/revtree" && ALLTAGBUILD="$OUT/bd-rev" OSUM_SMP=4 bash tools/alltag/build.sh "$OUT/rev" desk=no accel=kvm shot=no warten=0 \
    extra="r3alle wighalt=5 wigapp=/bin/wrace,run,/w0,1,4,1" progs="wrace wspam sh echo ls cat" > "$OUT/rev.log" 2>&1)
[ -s "$OUT/bd-rev/k0.mb" ] && [ -s "$OUT/rev/disk.img" ] && ok "kernel and disk of the copy (shared copy page) built" \
    || { bad "build of the copy"; tail -5 "$OUT/rev.log"; }

echo; echo "== 2. the fix holds: four writers + the taskbar's poll on four cores =="
guest cur "$OUT/bd-cur/k0.mb" "$OUT/cur/disk.img"
grep -aq 'wspam: done' "$OUT/cur.txt" && ok "the window-list poll ran ($(grep -ao 'listed=[0-9]*' "$OUT/cur.txt" | head -1))" || bad "the poll did not run"
grep -aq 'wrace: ok files=4' "$OUT/cur.txt" && ok "every octet the writers wrote is right" || { bad "wrace: $(grep -a 'wrace:' "$OUT/cur.txt" | head -2 | tr '\n' '|')"; }

echo; echo "== 3. NEGATIVE CONTROL: the shared copy page must lose octets =="
guest rev "$OUT/bd-rev/k0.mb" "$OUT/rev/disk.img"
grep -aq 'wspam: done' "$OUT/rev.txt" && ok "the poll ran on the copy too" || bad "the poll did not run on the copy"
if grep -aq 'wrace: BAD' "$OUT/rev.txt"; then
    ok "the copy LOSES octets: $(grep -a 'wrace: BAD' "$OUT/rev.txt" | head -1)"
else
    bad "the copy lost nothing -- this test would not have caught r200"
fi
grep -aq 'octet 3600' "$OUT/rev.txt" && ok "the damage is at octet 3600 of a block, the window-list record (3600 mod 512 = 16: the r200 symptom)" \
    || bad "no damage at octet 3600 seen"

echo
echo "=================================================================="
echo "  R200: $pass passed, $fail failed"
echo "=================================================================="
[ "$fail" = 0 ] || exit 1
exit 0
