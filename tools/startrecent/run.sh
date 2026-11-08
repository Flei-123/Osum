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
RECENT_SEED="${RECENT_SEED:-vplay,charmap}"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
finish() { echo "STARTRECENT: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
MUT="$OUT/mutant"
mkdir -p "$MUT"
cp -a kernel/user "$MUT/user"
python3 -I - "$MUT/user/launcher.fi" <<'PY'
import sys
path = sys.argv[1]
text = open(path, "rb").read()
call = b"    mru_load(n)\n"
if text.count(call) != 1:
    sys.exit("mutant: mru_load call not found")
open(path, "wb").write(text.replace(call, b""))
PY
[ $? -eq 0 ] || { bad "mutant source cannot be derived"; finish; }
if vendor/firn/bin/firnc -c "$MUT/user/launcher.fi" -o "$MUT/launcher.o" > "$MUT/cc.log" 2>&1 \
   && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$MUT/launcher.elf" "$MUT/launcher.o" 2>>"$MUT/cc.log"; then
    strip --strip-all "$MUT/launcher.elf"
    ok "mutant launcher (recents never loaded) builds"
else
    bad "mutant launcher does not build: $(head -5 "$MUT/cc.log")"; finish
fi

bash tools/design/audit.sh "$OUT/warm" accel=kvm nurbau=ja > "$OUT/warm.log" 2>&1
MUT_BUILD="$OUT/build-mut"
cp -a "$DESIGNBUILD" "$MUT_BUILD"
cp "$MUT/launcher.elf" "$MUT_BUILD/launcher.elf"
printf 'recent=%s\n' "$RECENT_SEED" > "$OUT/startrecent.conf"

run_case() {
    local name=$1 scale=$2 builddir=$3 script=$4 res=${5:-1280x800}
    local yres=${res#*x}
    local dir="$OUT/$name" dreh="$OUT/$name.txt"
    mkdir -p "$dir"
    sed "s/^klick 24,780\$/klick 24,$((yres-20))/" "tools/startrecent/$script" > "$dreh"
    DESIGNBUILD="$builddir" AUDIT_MKFS_EXTRA="/etc/startrecent.conf=$OUT/startrecent.conf@0644" \
        bash tools/design/audit.sh "$dir" accel=kvm uitrace=yes uiscale="$scale" res="$res" halt=$HALT_SECONDS drehbuch="$dreh" > "$OUT/$name.audit.log" 2>&1
}
run_case open1 1 "$DESIGNBUILD" open.txt &
run_case open2 2 "$DESIGNBUILD" open.txt "$WIDE_RES" &
run_case save1 1 "$DESIGNBUILD" save.txt &
run_case mut1 1 "$MUT_BUILD" open.txt &
wait

judge() {
    local name=$1 label=$2 mode=$3 want=$4 scale=${5:-1}
    local dir="$OUT/$name" line rc
    if [ ! -f "$dir/serial.txt" ]; then bad "$label: no serial log ($name)"; return; fi
    line=$(python3 -I tools/startrecent/check.py "$mode" "$dir/serial.txt" "$dir/menu.ppm" "$RECENT_SEED" "$scale")
    rc=$?
    if [ "$want" = green ] && [ $rc -eq 0 ]; then ok "$label: $line"
    elif [ "$want" = red ] && [ $rc -ne 0 ]; then ok "$label: $line"
    else bad "$label: $line"; fi
}
judge open1 "scale 1: seeded recents lead the Recommended block" order green 1
judge open2 "scale 2: seeded recents lead the Recommended block" order green 2
judge save1 "starting a programme writes it to the front of /etc/startrecent.conf" saved green 1
judge mut1 "mutant without mru_load: recents are not shown, judge stays red" order red 1
finish
