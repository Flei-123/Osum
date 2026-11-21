#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); fi
mkdir -p "$OUT"
OLD_TREE="$OUT/old-tree"
cleanup() {
    git worktree remove --force "$OLD_TREE" > /dev/null 2>&1
    [ -n "${KEEP:-}" ] || [ -n "${1:-}" ] || true
}
trap cleanup EXIT
export DESIGNBUILD="${DESIGNBUILD:-$OUT/build}"
export AUDIT_TIMEOUT="${AUDIT_TIMEOUT:-1700}"
MAX_PARALLEL=3
HALT_SECONDS=200
WIDE_RES=1920x1080
NARROW_RES=1280x800
BASE_REF=${SETTINGSDISPLAY_BASE:-origin/main}
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

printf 'timeout 3\nresolution 1024x768\n\nentry Osum\n    path boot():/osum.mb\n' > "$OUT/osboot.cfg"

drehbuch_driver() {
    local yres=$1
    cat <<DRE
warte 12
klick 24,$((yres-20))
warte 3
klickauf start_Settings
warte 12
warteauf settings: nav route=settings://personalization page=0 || 90
taste ctrl-f
tippe display
warte 3
taste ret
warte 3
klick 150,$((yres-300))
warteauf settings: rect name=dres || 60
warte 2
foto page
klickauf srectdres
warte 2
foto list
taste down
taste ret
warte 3
foto keep
klick 150,$((yres-300))
warteauf settings: rect name=drevert || 30
klickauf srectdrevert
warte 4
foto back
DRE
}

drehbuch_boot() {
    local yres=$1
    cat <<DRE
warte 12
klick 24,$((yres-20))
warte 3
klickauf start_Settings
warte 12
warteauf settings: nav route=settings://personalization page=0 || 90
taste ctrl-f
tippe display
warte 3
taste ret
warte 3
klick 150,$((yres-300))
warteauf settings: rect name=dres || 60
warte 2
foto bootpage
klickauf srectdres
warte 2
foto list
taste down
taste ret
warte 4
foto bootsaved
DRE
}

run_case() {
    local name=$1 scale=$2 res=$3 flavor=$4 tree=${5:-$ROOT} builddir=${6:-$DESIGNBUILD}
    local yres=${res#*x}
    local dir="$OUT/$name" dreh="$OUT/$name.txt"
    local card_args=() mkfs_extra=""
    mkdir -p "$dir"
    if [ "$flavor" = boot ]; then
        drehbuch_boot "$yres" > "$dreh"
        mkfs_extra="/sysesp/@755 /sysesp/osboot.cfg=$OUT/osboot.cfg@644:0:0"
    else
        drehbuch_driver "$yres" > "$dreh"
        card_args=(gpu=vmsvga extra=disp)
    fi
    (cd "$tree" && DESIGNBUILD="$builddir" AUDIT_MKFS_EXTRA="$mkfs_extra" \
        bash tools/design/audit.sh "$dir" accel=kvm uitrace=yes "${card_args[@]}" uiscale="$scale" res="$res" halt=$HALT_SECONDS drehbuch="$dreh" > "$OUT/$name.audit.log" 2>&1)
}

judge() {
    local name=$1 shot_name=$2 kind=$3 label=$4 expect=$5
    local shot="$OUT/$name/$shot_name.ppm"
    if [ ! -f "$shot" ]; then
        [ "$expect" = red ] && ok "$label: no screenshot (old page has no such control)" || bad "$label: no screenshot ($name/$shot_name)"
        return
    fi
    local line status
    line=$(python3 -I tools/settingsdisplay/check.py "$kind" "$shot")
    status=$?
    if [ "$expect" = green ] && [ $status -eq 0 ]; then ok "$label: $line"
    elif [ "$expect" = red ] && [ $status -ne 0 ]; then ok "$label: $line"
    else bad "$label: expected $expect ($line)"; fi
}

git worktree add --detach "$OLD_TREE" "$BASE_REF" > "$OUT/old-tree.log" 2>&1 || { bad "base worktree $BASE_REF: $(tail -1 "$OUT/old-tree.log")"; echo "SETTINGSDISPLAY: $pass passed, $fail failed"; exit 1; }

run_case drv1 1 $NARROW_RES driver
cp -a "$DESIGNBUILD" "$OUT/build-boot"
OLD_BUILD="$OUT/build-old"
mkdir -p "$OLD_BUILD"
SLOW=(
    "drv2 2 $WIDE_RES driver $ROOT $DESIGNBUILD"
    "boot1 1 $NARROW_RES boot $ROOT $OUT/build-boot"
    "old1 1 $NARROW_RES driver $OLD_TREE $OLD_BUILD"
)
running=0
for spec in "${SLOW[@]}"; do
    run_case $spec &
    running=$((running+1))
    if [ "$running" -ge "$MAX_PARALLEL" ]; then wait -n; running=$((running-1)); fi
done
wait

judge drv1 page page "display page, scale 1: path heading, sections, rows, brightness readout" green
judge drv2 page pagetop "display page, scale 2 (window shows the top rows): heading, brightness, night light, readout inside the card" green
judge drv1 list list "resolution dropdown lists several modes, scale 1" green
judge drv1 keep keep "mode change shows the keep card with Revert button, scale 1" green
judge drv1 back back "Revert restores 1280 x 800 and closes the card, scale 1" green
judge boot1 bootpage bootpage "without a driver: mode shown + Applies after the next restart, no keep card" green
judge boot1 bootsaved bootsaved "without a driver: choosing a mode saves for the next restart, no keep card" green
judge old1 page page "counter-probe: old display page does not match the new layout" red
judge old1 keep keep "counter-probe: old display page has no keep card after a click" red

cfg_line=$(python3 -I tools/osum/mkfs.py cat "$OUT/boot1/disk.img" /sysesp/osboot.cfg 2>/dev/null | grep -a '^resolution' | head -1)
case "$cfg_line" in
    "resolution 1024x768"|"") echo "  --    osboot.cfg line after the run: '${cfg_line:-not flushed}' (write-behind may not be on the image yet)" ;;
    resolution*) ok "osboot.cfg has a new resolution line: $cfg_line" ;;
esac

for n in drv1 drv2 boot1; do
    c=$(grep -acE 'CRASH|EXCEPTION' "$OUT/$n/serial.txt" 2>/dev/null; true)
    [ "${c:-0}" = 0 ] || bad "$n: crash lines $c"
done
echo "SETTINGSDISPLAY: $pass passed, $fail failed"
[ "$fail" = 0 ]
