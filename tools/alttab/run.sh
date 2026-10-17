#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/alttab/run.sh -- the Alt+Tab switcher (W1d): overlay with window pictures + titles, Tab forward, Shift+Tab back,
# Alt release switches, Esc cancels. One desktop boot with three windows, keys through QMP (so Alt can be HELD), the serial lines
# `wm: switcher open|step|commit|cancel n=.. sel=.. win=..` and `wm: fokus` say what happened, screenshots say what is seen.
# COUNTER-PROBE: the same driver on the tree before the switcher (ALTTAB_BASE, default = parent of the first W1d commit):
# old Alt+Tab switches at once on the first Tab (no panel, no switcher lines, focus moves while Alt is still held).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-$(mktemp -d)}
mkdir -p "$OUT"
BASE_COMMIT=${ALTTAB_BASE:-$(git log --format=%H --grep="^wm: Alt+Tab switcher" -1 | xargs -r -I{} git rev-parse {}^)}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "ALTTAB: skipped, no qemu"; exit 0; }
PROGS="desktop taskbar launcher settings theme explorer sh echo ls cat"

run_tree() { # tree out
    mkdir -p "$2"
    ( cd "$1" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
      ALLTAGBUILD="$2.build" bash tools/alltag/build.sh "$2" kbd=no warten=1 \
        extra="modfs osum wmshell wmdauer usb hidgen" hold=no uitrace=yes waitfor="eingabe: ber=" progs="$PROGS" \
        qemu="-device qemu-xhci -device usb-kbd -qmp unix:$2/qmp.sock,server,nowait" \
        hook="python3 $ROOT/tools/alttab/drive.py $2/qmp.sock \$SOCK $2/serial.txt $2" ) > "$2.log" 2>&1
}
fact() { sed -n "s/^$2=//p" "$1/scenes.txt" 2>/dev/null | tail -1; }

echo "== 1. new tree =="
run_tree "$ROOT" "$OUT/new" || true
[ -s "$OUT/new/scenes.txt" ] || { bad "driver wrote no scenes.txt"; tail -15 "$OUT/new.log"; echo "== ALTTAB: $pass green, $fail red =="; exit 1; }
N="$OUT/new"
[ "$(fact $N A_open_n)" -ge 3 ] 2>/dev/null && ok "the panel lists $(fact $N A_open_n) windows (>= 3)" || bad "panel lists $(fact $N A_open_n) windows, want >= 3"
[ "$(fact $N A_open)" = 1 ] && ok "A: Alt+Tab opens the switcher" || bad "A: no switcher open line"
[ "$(fact $N A_open_sel)" = 1 ] && ok "A: the second window (most recently used) is selected first" || bad "A: first selection $(fact $N A_open_sel), want 1"
[ "$(fact $N A_step)" = 2 ] && ok "A: Tab moves the selection to 2" || bad "A: Tab -> $(fact $N A_step), want 2"
[ "$(fact $N A_back)" = 1 ] && ok "A: Shift+Tab moves back to 1" || bad "A: Shift+Tab -> $(fact $N A_back), want 1"
[ "$(fact $N A_focus_changed_while_held)" = 0 ] && ok "A: no focus change while Alt is held" || bad "A: focus moved while Alt was held"
[ "$(fact $N A_commit)" = 1 ] && ok "A: releasing Alt commits" || bad "A: no commit on Alt release"
[ "$(fact $N A_focus_after)" != none ] && [ -n "$(fact $N A_focus_after)" ] \
    && ok "A: the focus moved right after the commit (wm: fokus id=$(fact $N A_focus_after))" || bad "A: no focus change after the commit"
[ "$(fact $N B_cancel)" = 1 ] && ok "B: Esc cancels" || bad "B: no cancel"
[ "$(fact $N B_commit_after_cancel)" = 0 ] && [ "$(fact $N B_focus_changed)" = 0 ] \
    && ok "B: after cancel no commit and no focus change" || bad "B: commit/focus after cancel"
[ "$(fact $N C_commit)" = 1 ] && ok "C: a quick Alt+Tab tap still switches" || bad "C: quick tap did not switch"
BO=$(fact $N D_band_open_vs_idle_px); BA=$(fact $N D_band_open_vs_after_px)
[ -n "$BO" ] && [ "$BO" -ge 20000 ] 2>/dev/null && ok "D: the panel is on the screen (centre band differs by $BO px)" || bad "D: panel not visible (band diff '$BO', want >= 20000)"
[ -n "$BA" ] && [ "$BA" -ge 20000 ] 2>/dev/null && ok "D: the panel is gone after the commit (band differs by $BA px from the open picture)" || bad "D: panel still there? ($BA)"
BB=$(fact $N E_band_back_vs_idle_px)
[ -n "$BB" ] && [ "$BB" -ge 0 ] && [ "$BB" -le 3000 ] 2>/dev/null && ok "E: back on the first window the centre band equals the idle picture again ($BB px differ, no panel left over)" || bad "E: band back vs idle differs by '$BB' px (want <= 3000)"

echo
echo "== 2. COUNTER-PROBE: tree before the switcher =="
if [ -n "$BASE_COMMIT" ] && git rev-parse -q --verify "$BASE_COMMIT^{commit}" >/dev/null 2>&1; then
    BT="$OUT/basetree"
    git worktree add -q --detach "$BT" "$BASE_COMMIT" 2>/dev/null
    mkdir -p "$BT/tools/alttab" && cp tools/alttab/drive.py "$BT/tools/alttab/"
    run_tree "$BT" "$OUT/old" || true
    git worktree remove --force "$BT" >/dev/null 2>&1
    O="$OUT/old"
    [ -s "$O/scenes.txt" ] && ok "old tree booted and was driven" || bad "old run wrote no scenes.txt"
    [ "$(fact $O A_open)" = 0 ] && ok "old: no switcher panel" || bad "old: switcher lines present"
    [ "$(fact $O A_focus_changed_while_held)" = 1 ] && ok "old: focus moves while Alt is still held (switch at once)" || bad "old: focus did not move while Alt held"
else
    echo "  (skipped: base commit '$BASE_COMMIT' not in this clone)"
fi
echo
echo "== ALTTAB: $pass green, $fail red =="
[ "$fail" -eq 0 ]
