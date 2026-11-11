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
BOX_SCALE1="26 80 584 450"
BOX_SCALE2="52 160 1168 905"
START_CLICK_X=24
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

. tools/lib/firnenv.sh
SRC="$OUT/mutant-src"
mkdir -p "$SRC"
git archive HEAD | tar -x -C "$SRC"
firnenv_prepare_old_tree "$SRC"
python3 -I - "$SRC/kernel/ui/kgui/kgstage.fi" <<'PY'
import sys
path = sys.argv[1]
text = open(path, "rb").read()
guarded = b"    if !kstate.mode_on(state, kstate.M_DESK) {\n        wmtermio.term_write(state, tw, p, n + 1)\n    }\n    var i: u64 = 0\n    while i < n {\n        serial.put"
plain = b"    wmtermio.term_write(state, tw, p, n + 1)\n    var i: u64 = 0\n    while i < n {\n        serial.put"
if text.count(guarded) != 1:
    sys.exit("mutant: guarded boot report writer not found")
open(path, "wb").write(text.replace(guarded, plain))
PY
if [ $? -ne 0 ]; then bad "mutant source cannot be derived"; echo "TERMCLEAN: $pass passed, $fail failed"; exit 1; fi

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
if [ ! -s "$OUT/k-mut.mb" ]; then bad "mutant kernel does not build: $(tail -3 "$OUT/k-mut.log")"; echo "TERMCLEAN: $pass passed, $fail failed"; exit 1; fi
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
    local name=$1 label=$2 mode=$3 box=$4
    local shot="$OUT/$name/term.ppm"
    if [ ! -f "$shot" ]; then bad "$label: no screenshot ($name)"; return; fi
    local line
    line=$(python3 -I tools/termclean/check.py "$shot" "$mode" $box)
    if [ $? -eq 0 ]; then ok "$label: $line"; else bad "$label: $line"; fi
}
serial_has() {
    grep -a -q "^USB  hc=" "$OUT/$1/serial.txt" 2>/dev/null
}

judge real1 "scale 1: terminal shows no boot report" clean "$BOX_SCALE1"
judge real2 "scale 2: terminal shows no boot report" clean "$BOX_SCALE2"
judge mut1 "mutant (boot report written to the terminal) is caught" dirty "$BOX_SCALE1"
if serial_has real1; then ok "boot report stays on the serial line"; else bad "boot report missing on the serial line"; fi
echo "TERMCLEAN: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
