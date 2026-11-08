#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/tbpreview/run.sh -- hover preview of the windows of an app on the taskbar.
#
#   bash /root/jarvis/bin/heavy bash tools/tbpreview/run.sh [s1|s2|nopreview|all]
#
# Run A (scenario.txt): hover an idle pin (no preview), hover the running terminal button (preview, above the bar, centred), leave (gone),
# start the explorer pin and hover it (preview of a PINNED running app). Run B (close.txt): hover the terminal button and click the close
# icon of its row at the position reported by run A (serial `taskview: close id=.. rc=0`).
# nopreview = COUNTER-PROOF: the same scenario on a tree whose tbpreview.step never opens (must FAIL).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
MODE=${1:-all}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
PINS="explorer,settings,taskmgr,edit"
TBX="align=center;labels=never;height=48;clock_lines=2;clock_date=1;clock_year4=1;tray_chevron=1"
boot() { # <tag> <tree> <res> <uiscale> <scenario>
    local tag=$1 tree=$2 res=$3 sc=$4 scn=$5
    ( cd "$tree" && DESIGNBUILD="${TBPREVIEW_BUILD:-$TMPD/build-$tag}" bash tools/design/eh6.sh "$TMPD/$tag" res=$res uiscale=$sc accel=kvm tafel=nein \
        pins="$PINS" tbextra="$TBX" drehbuch="$scn" > "$TMPD/$tag.log" 2>&1 )
    [ -n "${TBPREVIEW_OUT:-}" ] && { mkdir -p "$TBPREVIEW_OUT/$tag"; cp "$TMPD/$tag"/*.ppm "$TMPD/$tag/serial.txt" "$TMPD/$tag.log" "$TBPREVIEW_OUT/$tag/" 2>/dev/null; }
}
run_one() { # <tag> <tree> <res> <uiscale>
    local tag=$1 tree=$2 res=$3 sc=$4
    boot "$tag" "$tree" "$res" "$sc" "$ROOT/tools/tbpreview/scenario.txt"
    local xy
    xy=$(python3 -I tools/tbpreview/check.py coords "$TMPD/$tag/serial.txt" "$sc") || xy="0 0"
    sed "s/@CLOSEX@/${xy% *}/;s/@CLOSEY@/${xy#* }/" tools/tbpreview/close.txt > "$TMPD/$tag-close.txt"
    boot "$tag-c" "$tree" "$res" "$sc" "$TMPD/$tag-close.txt"
    python3 -I tools/tbpreview/check.py check "$TMPD/$tag" "$TMPD/$tag-c" "$sc" | tee "$TMPD/$tag.res"
}
rc=0
if [ "$MODE" = s1 ] || [ "$MODE" = all ]; then
    echo "== scale 1 (1280x800)"; run_one s1 "$ROOT" 1280x800 1
    [ "$(grep -c '^  FAIL' "$TMPD/s1.res")" -eq 0 ] || rc=1
fi
if [ "$MODE" = s2 ] || [ "$MODE" = all ]; then
    echo "== scale 2 (1920x1080)"; run_one s2 "$ROOT" 1920x1080 2
    [ "$(grep -c '^  FAIL' "$TMPD/s2.res")" -eq 0 ] || rc=1
fi
if [ "$MODE" = nopreview ]; then
    W=$(mktemp -d "$ROOT/../tbpreview-mut.XXXX")
    trap 'rm -rf "$TMPD" "$W"' EXIT
    git worktree add -q --detach "$W" HEAD || exit 2
    sed -i 's/^fn step(hover: u64, mx: u64, my: u64) -> bool {/&\n    return false/' "$W/kernel/user/taskbar/tbpreview.fi"
    echo "== counter-proof: preview never opens"; ( cd "$W" && ROOT="$W" run_one old "$W" 1280x800 1 )
    f=$(grep -c '^  FAIL' "$TMPD/old.res")
    git worktree remove --force "$W"
    if [ "$f" -ge 3 ]; then echo "  OK    counter-proof: $f checks fail without the preview"
    else echo "  FAIL  counter-proof: only $f checks fail without the preview"; rc=1; fi
fi
echo "TBPREVIEW: rc=$rc"
exit $rc
