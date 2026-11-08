#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
mkdir -p "$OUT"
export DESIGNBUILD="${DESIGNBUILD:-$OUT/build}"
export AUDIT_TIMEOUT="${AUDIT_TIMEOUT:-900}"
HALT_SECONDS=200
WIDE_RES=1920x1080
BOX_SCALE1="10 30 600 470"
BOX_SCALE2="30 60 1190 930"
START_CLICK_X=24
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
SRC="$OUT/mutant-src"
mkdir -p "$SRC"
git archive HEAD | tar -x -C "$SRC"
cp -a vendor/firn/bin "$SRC/vendor/firn/" 2>/dev/null
python3 -I - "$SRC/kernel/ui/wm/wmgeom.fi" <<'PY'
import sys
path = sys.argv[1]
text = open(path, "rb").read()
real = b"    let v: u64 = wmlayout.gs(state, wmlayout.S_TERMPAD)\n"
flat = b"    let v: u64 = 0\n"
if text.count(real) != 1:
    sys.exit("mutant: terminal pad reader not found")
open(path, "wb").write(text.replace(real, flat))
PY
if [ $? -ne 0 ]; then bad "mutant source cannot be derived"; echo "TERMPAD: $pass passed, $fail failed"; exit 1; fi

run_case() {
    local name=$1 scale=$2 builddir=$3 res=${4:-1280x800}
    local yres=${res#*x}
    local dir="$OUT/$name" dreh="$OUT/$name.txt"
    mkdir -p "$dir"
    {
        echo "warte 12"
        echo "klick $START_CLICK_X,$((yres-20))"; echo "warte 4"
        echo "klickauf start_Terminal"; echo "warte 14"
        echo "foto term"
    } > "$dreh"
    DESIGNBUILD="$builddir" bash tools/design/audit.sh "$dir" accel=kvm uitrace=yes uiscale="$scale" res="$res" halt=$HALT_SECONDS drehbuch="$dreh" > "$OUT/$name.audit.log" 2>&1
}

(cd "$SRC" && FIRNLIB="$SRC/lib" ./tools/build-kernel.sh "$OUT/k-mut.mb" > "$OUT/k-mut.log" 2>&1) &
MUT_PID=$!
bash tools/design/audit.sh "$OUT/warm" accel=kvm nurbau=ja > "$OUT/warm.log" 2>&1
wait "$MUT_PID"
if [ ! -s "$OUT/k-mut.mb" ]; then bad "mutant kernel does not build: $(tail -3 "$OUT/k-mut.log")"; echo "TERMPAD: $pass passed, $fail failed"; exit 1; fi
ok "real and mutant kernels build"
MUT_BUILD="$OUT/build-mut"
cp -a "$DESIGNBUILD" "$MUT_BUILD"
cp "$OUT/k-mut.mb" "$MUT_BUILD/k0.mb"
touch "$MUT_BUILD/k0.mb"

run_case real1 1 "$DESIGNBUILD" &
run_case real2 2 "$DESIGNBUILD" "$WIDE_RES" &
run_case mut1 1 "$MUT_BUILD" &
wait

judge() {
    local name=$1 label=$2 scale=$3 mode=$4 box=$5
    local shot="$OUT/$name/term.ppm"
    if [ ! -f "$shot" ]; then bad "$label: no screenshot ($name)"; return; fi
    local line
    line=$(python3 -I tools/termpad/check.py "$shot" "$scale" "$mode" $box)
    if [ $? -eq 0 ]; then ok "$label: $line"; else bad "$label: $line"; fi
}

judge real1 "scale 1: terminal text keeps its inner margin" 1 padded "$BOX_SCALE1"
judge real2 "scale 2: terminal text keeps its inner margin" 2 padded "$BOX_SCALE2"
judge mut1 "mutant (no inner margin) is caught" 1 flat "$BOX_SCALE1"
echo "TERMPAD: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
