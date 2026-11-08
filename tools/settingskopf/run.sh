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
NEW_PROVIDER=northgate
NEW_TARGET=harborstore
OLD_PROVIDER=southgate
OLD_TARGET=dockyardstore
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

write_kopf() {
    local file=$1 salt=$2 provider_key=$3 provider=$4 target_key=$5 target=$6
    printf 'format 1\n%s x\n%s %s\n%s %s\ncheck x\n' "$salt" "$provider_key" "$provider" "$target_key" "$target" > "$file"
}
write_kopf "$OUT/kopf-new" salt provider "$NEW_PROVIDER" target "$NEW_TARGET"
write_kopf "$OUT/kopf-old" salz anbieter "$OLD_PROVIDER" ziel "$OLD_TARGET"
{
    printf 'format 1\nsalt x\nprovider %s\ntarget %s\n' "$NEW_PROVIDER" "$NEW_TARGET"
    printf 'anbieter %s\nziel %s\ncheck x\n' "$OLD_PROVIDER" "$OLD_TARGET"
} > "$OUT/kopf-both"

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
MUT="$OUT/mutant"
mkdir -p "$MUT"
cp -a kernel/user "$MUT/user"
sed -i -e 's/"provider\\0"/"pxovider\\0"/' -e 's/"target\\0"/"txrget\\0"/' "$MUT/user/settings/setcore.fi"
if cmp -s kernel/user/settings/setcore.fi "$MUT/user/settings/setcore.fi"; then
    bad "mutant source is identical to the real source"; echo "SETTINGSKOPF: $pass passed, $fail failed"; exit 1
fi
if vendor/firn/bin/firnc -c "$MUT/user/settings.fi" -o "$MUT/settings.o" > "$MUT/cc.log" 2>&1 \
   && ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$MUT/settings.elf" "$MUT/settings.o" 2>>"$MUT/cc.log"; then
    strip --strip-all "$MUT/settings.elf"
    ok "mutant settings (new KOPF keys ignored) builds"
else
    bad "mutant settings does not build: $(head -5 "$MUT/cc.log")"; echo "SETTINGSKOPF: $pass passed, $fail failed"; exit 1
fi

run_case() {
    local name=$1 kopf=$2 scale=$3 builddir=${4:-$DESIGNBUILD} res=${5:-1280x800}
    local yres=${res#*x}
    local dir="$OUT/$name" dreh="$OUT/$name.txt" extra="/konto/ /konto/KOPF=$kopf"
    mkdir -p "$dir"
    {
        echo "warte 12"
        echo "klick 24,$((yres-20))"; echo "warte 3"
        echo "klickauf start_Settings"; echo "warte 12"
        echo "warteauf settings: nav route=settings://personalization page=0 || 90"
        echo "taste ctrl-f"; echo "tippe sync"; echo "warte 3"
        echo "taste ret"; echo "warte 4"
        echo "foto sync"
    } > "$dreh"
    DESIGNBUILD="$builddir" AUDIT_MKFS_EXTRA="$extra" \
        bash tools/design/audit.sh "$dir" accel=kvm uitrace=yes uiscale="$scale" res="$res" halt=$HALT_SECONDS drehbuch="$dreh" > "$OUT/$name.audit.log" 2>&1
}

run_case new1 "$OUT/kopf-new" 1
MUT_BUILD="$OUT/build-mut"
cp -a "$DESIGNBUILD" "$MUT_BUILD"
cp "$MUT/settings.elf" "$MUT_BUILD/settings.elf"
SLOW=(
    "new2 $OUT/kopf-new 2 $DESIGNBUILD $WIDE_RES"
    "old1 $OUT/kopf-old 1"
    "old2 $OUT/kopf-old 2 $DESIGNBUILD $WIDE_RES"
    "both1 $OUT/kopf-both 1"
    "none1 /dev/null 1"
    "mut1 $OUT/kopf-new 1 $MUT_BUILD"
)
running=0
for spec in "${SLOW[@]}"; do
    run_case $spec &
    running=$((running+1))
    if [ "$running" -ge "$MAX_PARALLEL" ]; then wait -n; running=$((running-1)); fi
done
wait

judge() {
    local name=$1 label=$2 provider=$3 target=$4
    local shot="$OUT/$name/sync.ppm"
    if [ ! -f "$shot" ]; then bad "$label: no screenshot ($name)"; return; fi
    local line
    line=$(python3 -I tools/settingskopf/check.py "$shot" "$provider" "$target")
    if [ $? -eq 0 ]; then ok "$label: $line"; else bad "$label: $line"; fi
}
judge_red() {
    local name=$1 label=$2 provider=$3 target=$4
    local shot="$OUT/$name/sync.ppm"
    if [ ! -f "$shot" ]; then bad "$label: no screenshot ($name)"; return; fi
    local line
    line=$(python3 -I tools/settingskopf/check.py "$shot" "$provider" "$target")
    if [ $? -ne 0 ]; then ok "$label: $line"; else bad "$label: judge stayed green ($line)"; fi
}

judge new1 "new spelling, scale 1" "$NEW_PROVIDER" "$NEW_TARGET"
judge new2 "new spelling, scale 2" "$NEW_PROVIDER" "$NEW_TARGET"
judge old1 "old spelling, scale 1" "$OLD_PROVIDER" "$OLD_TARGET"
judge old2 "old spelling, scale 2" "$OLD_PROVIDER" "$OLD_TARGET"
judge both1 "both spellings, new wins" "$NEW_PROVIDER" "$NEW_TARGET"
judge_red none1 "no KOPF shows no provider" "$NEW_PROVIDER" "$NEW_TARGET"
judge_red mut1 "counter-probe: mutant ignoring new keys fails the judge" "$NEW_PROVIDER" "$NEW_TARGET"

for n in new1 new2 old1 old2 both1 none1 mut1; do
    c=$(grep -acE 'CRASH|EXCEPTION' "$OUT/$n/serial.txt" 2>/dev/null; true)
    [ "${c:-0}" = 0 ] || bad "$n: crash lines $c"
done
echo "SETTINGSKOPF: $pass passed, $fail failed"
[ "$fail" = 0 ]
