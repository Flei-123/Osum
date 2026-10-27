#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
BASE=${MENUTHEME_BASE:-$(git log --format=%H --grep='^fui: resync the toolkit theme' -1 | xargs -r -I{} git rev-parse {}^)}
LIMIT=${MENUTHEME_LUMA_LIMIT:-80}
cleanup() { [ -n "${OLD:-}" ] && git worktree remove --force "$OLD" >/dev/null 2>&1; rm -rf "$TMPD"; }
trap cleanup EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

shoot() {
    local tree=$1 out=$2
    ( cd "$tree" && DESIGNBUILD="$out-build" bash tools/design/audit.sh "$out" accel=kvm uitrace=yes halt=330 \
        mode=light scheme=day drehbuch="$ROOT/tools/menutheme/plan.txt" ) > "$out.log" 2>&1
}

luma() {
    python3 -I "$ROOT/tools/menutheme/crop.py" "$1" "$1.crop.png" || return 2
    python3 -I "$ROOT/tools/i18naudit/check.py" luma "$1.crop.png" "$LIMIT" dark
}

echo "== 1. light boot, theme switched to dark at run time, start menu opened =="
shoot "$ROOT" "$TMPD/new"
if [ -f "$TMPD/new/03-menu-after.ppm" ]; then
    luma "$TMPD/new/03-menu-after.ppm" > "$TMPD/l1.txt" && ok "start menu follows the run-time dark switch: $(tr -s ' ' < "$TMPD/l1.txt")" || bad "start menu stayed light: $(tr -s ' ' < "$TMPD/l1.txt")"
    cp "$TMPD/new/03-menu-after.ppm" "${MENUTHEME_KEEP:-/dev/null}" 2>/dev/null
else
    bad "no screenshot from the new tree: $(tail -n 1 "$TMPD/new.log" | cut -c1-100)"
fi

echo "== 2. counter-probe: tree before the fix =="
if [ -z "$BASE" ]; then bad "no base commit for the counter-probe"; else
    OLD="$TMPD/old"
    git worktree add --detach "$OLD" "$BASE" > "$TMPD/wt.log" 2>&1 || bad "worktree failed: $(tail -n 2 "$TMPD/wt.log")"
    if [ -d "$OLD" ]; then
        ( cd "$OLD" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 )
        shoot "$OLD" "$TMPD/old-out"
        if [ -f "$TMPD/old-out/03-menu-after.ppm" ]; then
            luma "$TMPD/old-out/03-menu-after.ppm" > "$TMPD/l2.txt" && bad "old tree menu is dark too, the probe sees nothing: $(tr -s ' ' < "$TMPD/l2.txt")" || ok "old tree menu stays light: $(tr -s ' ' < "$TMPD/l2.txt")"
        else
            bad "no screenshot from the old tree"
        fi
    fi
fi
echo "== MENUTHEME: $pass green, $fail red =="
[ "$fail" -eq 0 ]
