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
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
finish() { echo "STARTNAV: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }

. tools/lib/firnenv.sh
MUT="$OUT/mutant"
mkdir -p "$MUT"
cp -a kernel/user "$MUT/user"
python3 -I - "$MUT/user/launcher.fi" <<'PY'
import sys
path = sys.argv[1]
text = open(path, "rb").read()
call = b"            home_arrow(fuiscene.key_any())\n"
if text.count(call) != 1:
    sys.exit("mutant: arrow call not found")
open(path, "wb").write(text.replace(call, b""))
PY
[ $? -eq 0 ] || { bad "mutant source cannot be derived"; finish; }
if "$FIRNC" -c "$MUT/user/launcher.fi" -o "$MUT/launcher.o" > "$MUT/cc.log" 2>&1 \
   && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$MUT/launcher.elf" "$MUT/launcher.o" 2>>"$MUT/cc.log"; then
    strip --strip-all "$MUT/launcher.elf"
    ok "mutant launcher (arrow keys ignored) builds"
else
    bad "mutant launcher does not build: $(head -5 "$MUT/cc.log")"; finish
fi

bash tools/design/audit.sh "$OUT/warm" accel=kvm nurbau=ja > "$OUT/warm.log" 2>&1
MUT_BUILD="$OUT/build-mut"
cp -a "$DESIGNBUILD" "$MUT_BUILD"
cp "$MUT/launcher.elf" "$MUT_BUILD/launcher.elf"

run_case() {
    local name=$1 scale=$2 builddir=$3 res=${4:-1280x800}
    local yres=${res#*x}
    local dir="$OUT/$name" dreh="$OUT/$name.txt"
    mkdir -p "$dir"
    sed "s/^klick 24,780\$/klick 24,$((yres-20))/" tools/startnav/nav.txt > "$dreh"
    DESIGNBUILD="$builddir" bash tools/design/audit.sh "$dir" accel=kvm uitrace=yes uiscale="$scale" res="$res" halt=$HALT_SECONDS drehbuch="$dreh" > "$OUT/$name.audit.log" 2>&1
}
run_case real1 1 "$DESIGNBUILD" &
run_case real2 2 "$DESIGNBUILD" "$WIDE_RES" &
run_case mut1 1 "$MUT_BUILD" &
wait

judge() {
    local name=$1 label=$2 shot=$3 expected=$4 scale=$5 want=$6
    local ppm="$OUT/$name/$shot.ppm"
    if [ ! -f "$ppm" ]; then bad "$label: no screenshot ($name/$shot)"; return; fi
    local line rc
    line=$(python3 -I tools/startnav/check.py "$ppm" "$OUT/$name/serial.txt" "$expected" "$scale")
    rc=$?
    if [ "$want" = green ] && [ $rc -eq 0 ]; then ok "$label: $line"
    elif [ "$want" = red ] && [ $rc -ne 0 ]; then ok "$label: $line"
    else bad "$label: $line"; fi
}
for spec in "1 real1" "2 real2"; do
    scale=${spec% *}; name=${spec#* }
    judge "$name" "scale $scale: menu opens without a tile ring" 00-open -1 "$scale" green
    judge "$name" "scale $scale: Down from the search field rings tile 100" 01-down 100 "$scale" green
    judge "$name" "scale $scale: Right rings tile 101" 02-right 101 "$scale" green
    judge "$name" "scale $scale: Right again rings tile 102" 03-right2 102 "$scale" green
    judge "$name" "scale $scale: Left goes back to tile 101" 04-left 101 "$scale" green
    judge "$name" "scale $scale: Up leaves the grid" 05-up -1 "$scale" green
done
judge mut1 "mutant without arrow handling: Down rings nothing, judge stays red" 01-down 100 1 red
finish
