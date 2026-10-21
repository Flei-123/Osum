#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
BASE=${BASE:-7c767dae}
TMPD=$(mktemp -d)
BWT=""
cleanup() {
    rm -rf "$TMPD"
    if [ -n "$BWT" ]; then git worktree remove --force "$BWT" >/dev/null 2>&1; fi
}
trap cleanup EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { local name=$1 val=$2 op=$3 want=$4
    if [ -z "${val:-}" ]; then bad "$name: no number (expected $op $want)"; return; fi
    if [ "$val" -"$op" "$want" ] 2>/dev/null; then ok "$name: $val"
    else bad "$name: $val, expected $op $want"; fi
}
cnt() { grep -ac "$2" "$1" 2>/dev/null || true; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { echo "fetch-firnc failed"; exit 1; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "TASKMGR2: skipped, no qemu"; exit 0; }

drive() {
    local tree=$1 out=$2 plan=$3
    ( cd "$tree" && bash tools/toolbench/build.sh "$out" desk=yes \
        app=/bin/taskmgr,melde,takt,500 wait=14 last=400 extra="wighalt=120" \
        plan="$plan" > "$out.log" 2>&1 )
}

echo "== 1. context menu on a process row =="
drive "$ROOT" "$TMPD/c" "$ROOT/tools/taskmgr2/ctx.txt" || bad "build ctx"
SC="$TMPD/c/serial.txt"
num "plan targets not found" "$(cnt "$TMPD/c/plan.log" 'ZIEL NICHT GEFUNDEN')" eq 0
num "menu opened (2 row clicks, 1 header miss)" "$(cnt "$SC" '^taskmgr: ctx n=')" eq 2
num "menu has 2 rows" "$(grep -a '^taskmgr: ctx n=' "$SC" | head -1 | sed -E 's/.*ctx n=([0-9]+).*/\1/')" eq 2
LPID=$(grep -a '^taskmgr: zeile' "$SC" | grep 'name=launcher' | head -1 | grep -oE ' pid=[0-9]+' | sed 's/.*=//')
CPID=$(grep -a '^taskmgr: ctx n=' "$SC" | head -1 | sed -E 's/.* pid=([0-9]+).*/\1/')
[ -n "${LPID:-}" ] && [ "${LPID:-x}" = "${CPID:-y}" ] && ok "menu belongs to the clicked row (pid $CPID)" || bad "menu pid ${CPID:-?}, row pid ${LPID:-?}"
num "exactly one pick (Escape picks nothing)" "$(cnt "$SC" '^taskmgr: ctx wahl act=')" eq 1
num "picked action is details (2)" "$(grep -a '^taskmgr: ctx wahl act=' "$SC" | head -1 | sed -E 's/.*act=([0-9]+).*/\1/')" eq 2
num "no end-task question asked" "$(cnt "$SC" '^taskmgr: frage pid=')" eq 0
BOX=$(python3 -I tools/toolbench/klickplan.py "$SC" ctxbox 2>/dev/null)
if [ -n "$BOX" ] && [ -s "$TMPD/c/c00_before.ppm" ] && [ -s "$TMPD/c/c01_open.ppm" ] && [ -s "$TMPD/c/c02_closed.ppm" ]; then
    python3 -I - "$TMPD/c" "$BOX" > "$TMPD/ctxpix.txt" 2>&1 <<'PY'
import sys
from PIL import Image, ImageChops
d, box = sys.argv[1], [int(v) for v in sys.argv[2].split(",")]
x, y, w, h = box
def crop(n):
    return Image.open("%s/%s.ppm" % (d, n)).convert("RGB").crop((x, y, x + w, y + h))
def frac(a, b):
    diff = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > 24 else 0)
    return sum(1 for v in diff.getdata() if v) / float(w * h)
opened = frac(crop("c00_before"), crop("c01_open"))
closed = frac(crop("c00_before"), crop("c02_closed"))
print("opened=%.3f closed=%.3f" % (opened, closed))
raise SystemExit(0 if opened > 0.30 and closed < 0.05 else 1)
PY
    [ $? -eq 0 ] && ok "menu is painted and Escape removes it ($(cat "$TMPD/ctxpix.txt"))" || bad "menu pixels: $(cat "$TMPD/ctxpix.txt")"
else
    bad "no menu box or photos"
fi

echo
echo "== 2. search field filters the list =="
drive "$ROOT" "$TMPD/s" "$ROOT/tools/taskmgr2/search.txt" || bad "build search"
SS="$TMPD/s/serial.txt"
num "plan targets not found" "$(cnt "$TMPD/s/plan.log" 'ZIEL NICHT GEFUNDEN')" eq 0
ALL=$(grep -a '^taskmgr: group' "$SS" | head -1 >/dev/null; grep -a '^taskmgr: zeile' "$SS" | grep -oE ' pid=[0-9]+' | sort -u | wc -l)
NOMATCH=$(grep -a '^taskmgr: search n=' "$SS" | sed -E 's/.*n=([0-9]+).*/\1/' | sed -n 3p)
LAST=$(grep -a '^taskmgr: search n=' "$SS" | tail -1 | sed -E 's/.*n=([0-9]+).*/\1/')
echo "        search values: $(grep -a '^taskmgr: search n=' "$SS" | sed -E 's/.*n=([0-9]+).*/\1/' | tr '\n' ' ') (processes: $ALL)"
num "typing 'zzq' leaves no process rows" "${NOMATCH:-99}" le 3
num "typing 'lau' finds the launcher" "${LAST:-0}" ge 2
num "and filters the list" "${LAST:-99}" lt $((ALL + 3))

echo
echo "== 3. counter-proof: the tree before S1 fails the same plans =="
BWT="$TMPD/basewt"
if git worktree add --detach "$BWT" "$BASE" >/dev/null 2>&1; then
    mkdir -p "$BWT/tools/taskmgr2"
    cp -r tools/toolbench/. "$BWT/tools/toolbench/"
    cp tools/taskmgr2/ctx.txt tools/taskmgr2/search.txt "$BWT/tools/taskmgr2/"
    drive "$BWT" "$TMPD/bc" "$BWT/tools/taskmgr2/ctx.txt" || true
    drive "$BWT" "$TMPD/bs" "$BWT/tools/taskmgr2/search.txt" || true
    num "BASE $BASE: no context menu opens" "$(cnt "$TMPD/bc/serial.txt" '^taskmgr: ctx n=')" eq 0
    num "BASE $BASE: no search events" "$(cnt "$TMPD/bs/serial.txt" '^taskmgr: search n=')" eq 0
    num "BASE $BASE: plan cannot find its targets" "$(( $(cnt "$TMPD/bc/plan.log" 'ZIEL NICHT GEFUNDEN') + $(cnt "$TMPD/bs/plan.log" 'ZIEL NICHT GEFUNDEN') ))" ge 1
else
    bad "cannot create the BASE worktree $BASE"
fi

echo
if [ "$fail" -eq 0 ]; then echo "TASKMGR2: $pass passed, 0 failed"; exit 0; fi
echo "TASKMGR2: $pass passed, $fail FAILED"
exit 1
