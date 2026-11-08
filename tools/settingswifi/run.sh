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
MAX_PARALLEL=3
HALT_SECONDS=200
WIDE_RES=1920x1080
NARROW_RES=1280x800
FIRMWARE_PATH=/lib/firmware/intel/iwlwifi/iwlwifi-8265-36.ucode
ADAPTER_WORDS="iwlfhtest iwlfhbind"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$OUT/blobs"
if ! python3 -I tools/iwlfh/ref.py gen "$OUT/blobs" > "$OUT/blobs.log" 2>&1; then
    bad "firmware reference blobs"; echo "SETTINGSWIFI: $pass passed, $fail failed"; exit 1
fi
MUT="$OUT/mutant"
mkdir -p "$MUT"
cp -a kernel/user "$MUT/user"
python3 -I - "$MUT/user/settings.d/builtin.settings" <<'PY'
import sys
source = sys.argv[1]
text = open(source, encoding="utf-8").read()
condition = "when wifi-adapter\n"
if condition not in text:
    sys.exit("mutant anchor missing")
open(source, "w", encoding="utf-8").write(text.replace(condition, ""))
PY
if [ $? -ne 0 ] || cmp -s kernel/user/settings.d/builtin.settings "$MUT/user/settings.d/builtin.settings"; then
    bad "mutant source is identical to the real source"; echo "SETTINGSWIFI: $pass passed, $fail failed"; exit 1
fi
if vendor/firn/bin/firnc -c "$MUT/user/settings.fi" -o "$MUT/settings.o" > "$MUT/cc.log" 2>&1 \
   && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$MUT/settings.elf" "$MUT/settings.o" 2>>"$MUT/cc.log"; then
    strip --strip-all "$MUT/settings.elf"
    ok "mutant settings (Wi-Fi fields without the adapter condition) builds"
else
    bad "mutant settings does not build: $(head -5 "$MUT/cc.log")"; echo "SETTINGSWIFI: $pass passed, $fail failed"; exit 1
fi

run_case() {
    local name=$1 scale=$2 res=$3 builddir=${4:-$DESIGNBUILD} adapter=${5:-no}
    local yres=${res#*x}
    local extra_arg=() mkfs_extra="/lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/"
    if [ "$adapter" = yes ]; then
        extra_arg=("extra=$ADAPTER_WORDS")
        mkfs_extra="$mkfs_extra $FIRMWARE_PATH=$OUT/blobs/v7.bin"
    fi
    local dir="$OUT/$name" dreh="$OUT/$name.txt"
    mkdir -p "$dir"
    {
        echo "warte 12"
        echo "klick 24,$((yres-20))"; echo "warte 3"
        echo "klickauf start_Settings"; echo "warte 12"
        echo "warteauf settings: nav route=settings://personalization page=0 || 90"
        echo "taste ctrl-f"; echo "tippe wireless"; echo "warte 3"
        echo "taste ret"; echo "warte 8"
        echo "foto wifi"
    } > "$dreh"
    DESIGNBUILD="$builddir" AUDIT_PROC=1 AUDIT_MKFS_EXTRA="$mkfs_extra" \
        bash tools/design/audit.sh "$dir" accel=kvm uitrace=yes fs=an "${extra_arg[@]}" uiscale="$scale" res="$res" halt=$HALT_SECONDS drehbuch="$dreh" > "$OUT/$name.audit.log" 2>&1
}

MUT_BUILD="$OUT/build-mut"
run_case real1 1 $NARROW_RES
cp -a "$DESIGNBUILD" "$MUT_BUILD"
cp "$MUT/settings.elf" "$MUT_BUILD/settings.elf"
SLOW=(
    "real2 2 $WIDE_RES $DESIGNBUILD no"
    "adapter1 1 $NARROW_RES $DESIGNBUILD yes"
    "adapter2 2 $WIDE_RES $DESIGNBUILD yes"
    "mut1 1 $NARROW_RES $MUT_BUILD no"
)
running=0
for spec in "${SLOW[@]}"; do
    run_case $spec &
    running=$((running+1))
    if [ "$running" -ge "$MAX_PARALLEL" ]; then wait -n; running=$((running-1)); fi
done
wait

judge() {
    local name=$1 kind=$2 label=$3 expect=$4
    local shot="$OUT/$name/wifi.ppm"
    if [ ! -f "$shot" ]; then bad "$label: no screenshot ($name/wifi)"; return; fi
    local line status
    line=$(python3 -I tools/settingswifi/check.py "$kind" "$shot")
    status=$?
    if [ "$expect" = green ] && [ $status -eq 0 ]; then ok "$label: $line"
    elif [ "$expect" = red ] && [ $status -ne 0 ]; then ok "$label: $line"
    else bad "$label: expected $expect ($line)"; fi
}

judge real1 noadapter "no adapter, scale 1: message shown, Refresh and Connect hidden" green
judge real2 noadapter "no adapter, scale 2: message shown, Refresh and Connect hidden" green
judge adapter1 adapter "with adapter, scale 1: Refresh and Connect shown, no message" green
judge adapter2 adapter "with adapter, scale 2: Refresh and Connect shown, no message" green
judge mut1 noadapter "counter-probe: old always-on buttons without adapter" red

for n in real1 real2 adapter1 mut1; do
    c=$(grep -acE 'CRASH|EXCEPTION' "$OUT/$n/serial.txt" 2>/dev/null; true)
    [ "${c:-0}" = 0 ] || bad "$n: crash lines $c"
done
echo "SETTINGSWIFI: $pass passed, $fail failed"
[ "$fail" = 0 ]
