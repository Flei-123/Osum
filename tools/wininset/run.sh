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
export AUDIT_TIMEOUT="${AUDIT_TIMEOUT:-1700}"
HALT_SECONDS=150
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

. tools/lib/firnenv.sh
MUT="$OUT/mutant"
mkdir -p "$MUT"
cp -a kernel/user "$MUT/user"
python3 -I - "$MUT/user/settings.fi" <<'PY'
import sys
path = sys.argv[1]
text = open(path, "rb").read().decode("utf-8")
edits = (
    ("setcore.sayn(wlib.win_cx(setbase.w))", "setcore.sayn(wlib.win_x(setbase.w) + 2)"),
    ("setcore.sayn(wlib.win_cy(setbase.w))", "setcore.sayn(wlib.win_y(setbase.w) + 22)"),
)
for old, new in edits:
    if text.count(old) != 1:
        sys.exit("mutant anchor missing: " + old)
    text = text.replace(old, new)
open(path, "wb").write(text.encode("utf-8"))
PY
if [ $? -ne 0 ] || cmp -s kernel/user/settings.fi "$MUT/user/settings.fi"; then
    bad "mutant source is identical to the real source"; echo "WININSET: $pass passed, $fail failed"; exit 1
fi
if "$FIRNC" -c "$MUT/user/settings.fi" -o "$MUT/settings.o" > "$MUT/cc.log" 2>&1 \
   && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$MUT/settings.elf" "$MUT/settings.o" 2>>"$MUT/cc.log"; then
    strip --strip-all "$MUT/settings.elf"
    ok "mutant settings (fixed 2/22 client origin) builds"
else
    bad "mutant settings does not build: $(head -5 "$MUT/cc.log")"; echo "WININSET: $pass passed, $fail failed"; exit 1
fi

run_case() {
    local name=$1 scale=$2 res=$3 builddir=${4:-$DESIGNBUILD}
    local yres=${res#*x}
    local dir="$OUT/$name" dreh="$OUT/$name.txt"
    mkdir -p "$dir"
    {
        echo "warte 12"
        echo "klick 24,$((yres-20))"; echo "warte 3"
        echo "klickauf start_Settings"; echo "warte 12"
        echo "warteauf settings: nav route=settings://personalization page=0 || 90"
        echo "warte 3"
        echo "foto window"
    } > "$dreh"
    DESIGNBUILD="$builddir" bash tools/design/audit.sh "$dir" accel=kvm uitrace=yes uiscale="$scale" res="$res" halt=$HALT_SECONDS drehbuch="$dreh" > "$OUT/$name.audit.log" 2>&1
}

MUT_BUILD="$OUT/build-mut"
run_case real1 1 1280x800
cp -a "$DESIGNBUILD" "$MUT_BUILD"
cp "$MUT/settings.elf" "$MUT_BUILD/settings.elf"
run_case real2 2 1920x1080 &
run_case mut1 1 1280x800 "$MUT_BUILD" &
wait

judge() {
    local name=$1 scale=$2 expect=$3 label=$4
    local line status
    line=$(python3 -I tools/wininset/check.py "$OUT/$name/serial.txt" "$scale" "$OUT/$name" 2>&1)
    status=$?
    if [ "$expect" = green ] && [ $status -eq 0 ]; then ok "$label: $line"
    elif [ "$expect" = red ] && [ $status -ne 0 ]; then ok "$label: $line"
    else bad "$label: expected $expect ($line)"; fi
}

judge real1 1 green "settings window: client origin equals the WM inset of the shape, widget ax/ay chain, scale 1"
judge real2 2 green "settings window: client origin equals the WM inset of the shape, widget ax/ay chain, scale 2"
judge mut1 1 red "counter-probe: fixed 2/22 client origin is rejected"

for n in real1 real2 mut1; do
    c=$(grep -acE 'CRASH|EXCEPTION' "$OUT/$n/serial.txt" 2>/dev/null; true)
    [ "${c:-0}" = 0 ] || bad "$n: crash lines $c"
done
echo "WININSET: $pass passed, $fail failed"
[ "$fail" = 0 ]
