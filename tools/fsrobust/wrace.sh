#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fsrobust/wrace.sh -- DAILY-DRIVER: WRITERS ON FOUR CORES, CHECKED
# BY THE HOST.
#
#   bash tools/fsrobust/wrace.sh [rounds]
#
# Roadmap r200 (27.09.2026): an installed system came up with a broken file
# system -- 128 octets from byte 16 of a sector zeroed at random; before
# that the Dell update had pieces of another file written onto the stick.
# The fix of that day gave every core its own copy page
# (kstate.BLOCKK_OFF); nothing checks that it holds. This does:
#
#   1. /bin/wrace starts four writers (`-smp 4 r3alle`, ring 3 on all
#      cores), each writes its own file in 4 KiB blocks from a pattern that
#      depends on the file AND the octet, with a read of another file
#      between the writes -- the traffic that corrupted the stick
#   2. the guest compares every octet it wrote (it reads through the same
#      kernel it is testing, so it is not trusted alone) ...
#   3. ... and AFTER THE GUEST HAS SHUT DOWN the host reads every file off
#      the disk image with mkfs.py, the second implementation of the
#      format, and recomputes the pattern in Python
#   4. a second boot from the same disk compares everything again, with
#      the kernel's caches empty
#   GEGENPROBE: one octet of the image is flipped on the host and the
#   host check must see it; without that a checker that always says "ok"
#   would pass for ever.
#
# WHAT THIS CANNOT SAY, MEASURED ON 02.10.2026: that the copy-page race of
# r200 is gone. The shared page was put back on purpose (blockb = BLOCK_OFF
# for everybody) and three rounds still passed -- the writers share the
# file-system lock, so they never meet in the page. What the test does
# prove: four writers on four cores lose and mix up nothing, the guest
# and the host agree on every octet, and the files survive a restart.
# Roadmap r200 therefore stays open for what it names: the DESKTOP on four
# cores (window calls + file writes) -- tools/multicore/run.sh is the place
# for a negative control.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/qemu.sh
OUT=${OUT:-/tmp/wrace-run}
mkdir -p "$OUT"
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/sperre.sh" && osum_sperre "$OUT"
export OUT
ROUNDS=${1:-2}
PROCS=4
KIB=${WRACE_KIB:-256}
export OSUM_CPU=${OSUM_CPU:-Haswell}

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
gleich() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi; }
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }

# the host side of the pattern (the same function as kernel/user/wrace.fi `pat`)
cat > "$OUT/check.py" <<'PY'
import subprocess, sys
img, d, procs, kib = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
bad = 0
for n in range(procs):
    p = subprocess.run([sys.executable, "tools/osum/mkfs.py", "cat", img, "%s/f%d" % (d, n)],
                       capture_output=True)
    data = p.stdout
    want = bytes((((o * 131) + (n * 17) + ((o >> 12) * 7)) & 255) ^ 0x5A for o in range(kib * 1024))
    if data == want:
        continue
    bad += 1
    if len(data) != len(want):
        print("host: f%d has %d octets, expected %d" % (n, len(data), len(want)))
    else:
        for o in range(len(want)):
            if data[o] != want[o]:
                print("host: f%d block %d octet %d: got %d want %d"
                      % (n, o // 4096, o % 4096, data[o], want[o]))
                break
print("host: ok files=%d" % procs if bad == 0 else "host: FAILED bad=%d" % bad)
sys.exit(1 if bad else 0)
PY

for t in qemu-system-x86_64 python3; do
    command -v "$t" >/dev/null 2>&1 || { echo "WRACE: uebersprungen, $t fehlt"; exit 0; }
done

echo "== 1. build: kernel, /bin/wrace, an image that carries it, an empty data disk =="
bash vendor/firn/fetch-firnc.sh > "$OUT/firnc.log" 2>&1 \
    && ok "the pinned compiler" || { bad "fetch-firnc.sh"; tail -5 "$OUT/firnc.log"; }
bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 \
    && ok "image built" || { bad "tools/install/build.sh"; tail -20 "$OUT/build.log"; }
[ -s "$OUT/bin/wrace" ] && ok "/bin/wrace is in the image ($(stat -c%s "$OUT/bin/wrace") octets)" || bad "/bin/wrace missing"
# the ROOT disk is the test disk: the image of the module (an OFS with the
# programs and about 5 MiB free) is the disk the kernel boots from (`roh`),
# so the writers hit the file system a real installation runs from. A
# second OFS cannot be mounted (kernel/vfs.fi mounts the root again).
cp -f "$OUT/quelle.img" "$OUT/ziel.img"
python3 tools/osum/mkfs.py list "$OUT/ziel.img" | head -1 | sed 's/^/        /'

guest() { # name script [limit]
    OSUM_SMP=4 OSUM_EXTRA="r3alle" OUT="$OUT" \
        bash tools/install/oneshot.sh "$1" roh "$2" "${3:-900}" > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' -e 's/\r//g' "$OUT/$1.txt" 2>/dev/null
    cat "$OUT/$1.rc" 2>/dev/null
}

for r in $(seq 1 "$ROUNDS"); do
    echo
    echo "== 2.$r round $r: $PROCS writers x $KIB KiB, four cores =="
    D="/w$r"
    rc=$(guest "w$r" "wrace run $D $PROCS $KIB;exit")
    gleich "round $r: the machine comes up and shuts down" "$rc" "21"
    hat "$OUT/w$r.txt" "wrace: ok files=$PROCS" "round $r: the guest finds every octet it wrote"
    if grep -qa "wrace: BAD" "$OUT/w$r.txt"; then
        bad "round $r: $(grep -a 'wrace: BAD' "$OUT/w$r.txt" | head -2 | tr '\n' '|')"
    fi
    python3 "$OUT/check.py" "$OUT/ziel.img" "$D" "$PROCS" "$KIB" > "$OUT/h$r.txt" 2>&1 \
        && ok "round $r: the HOST reads every file off the disk image and every octet is right" \
        || { bad "round $r: the host check: $(tr '\n' '|' < "$OUT/h$r.txt")"; }
done

echo
echo "== 3. a second boot reads it all again, caches empty =="
rc=$(guest wv "wrace verify /w1 $PROCS $KIB;exit" 600)
hat "$OUT/wv.txt" "wrace: ok files=$PROCS" "after a restart the files are still right"

echo
echo "== 4. GEGENPROBE: one flipped octet on the image must be seen by the host =="
cp "$OUT/ziel.img" "$OUT/flip.img"
WH=$(python3 tools/osum/mkfs.py where "$OUT/flip.img" /w1/f2 2>&1)
FB=$(echo "$WH" | sed -n 's/.*first=\([0-9]*\).*/\1/p')
if [ -n "$FB" ]; then
    python3 - "$OUT/flip.img" "$FB" <<'PY'
import sys
img, blk = sys.argv[1], int(sys.argv[2])
with open(img, "r+b") as f:
    f.seek(blk * 512 + 100)
    b = f.read(1)
    f.seek(blk * 512 + 100)
    f.write(bytes([b[0] ^ 0xFF]))
PY
    if python3 "$OUT/check.py" "$OUT/flip.img" /w1 "$PROCS" "$KIB" > "$OUT/hflip.txt" 2>&1; then
        bad "the host check did NOT see a flipped octet -- it measures nothing"
    else
        ok "the host check sees the flipped octet ($(grep -a '^host: f' "$OUT/hflip.txt" | head -1))"
    fi
else
    bad "mkfs.py where gave no block ($WH)"
fi

echo
echo "=================================================================="
echo "  WRACE: $pass passed, $fail failed"
echo "=================================================================="
[ "$fail" = 0 ] || exit 1
exit 0
