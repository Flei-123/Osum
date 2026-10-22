#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
BASE=${BASE:-7c767dae}
TMPD=${TM2_OUT:-$(mktemp -d)}
mkdir -p "$TMPD"
BWT=""
cleanup() {
    [ -n "${TM2_OUT:-}" ] || rm -rf "$TMPD"
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
num "menu on the launcher (an app) has exactly 3 rows" "$(grep -a '^taskmgr: ctx n=' "$SC" | head -1 | sed -E 's/.*ctx n=([0-9]+).*/\1/')" eq 3
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
    return diff.histogram()[255] / float(w * h)
flip = frac(crop("c01_open"), crop("c02_closed"))
print("menu_open_vs_closed=%.3f" % flip)
raise SystemExit(0 if flip > 0.30 else 1)
PY
    [ $? -eq 0 ] && ok "menu is painted and Escape changes the area ($(cat "$TMPD/ctxpix.txt"))" || bad "menu pixels: $(cat "$TMPD/ctxpix.txt")"
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
num "typing 'laun' leaves a heading and the launcher" "${LAST:-0}" eq 2
num "an empty field shows all rows again" "$(grep -a '^taskmgr: search n=' "$SS" | sed -E 's/.*n=([0-9]+).*/\1/' | sort -n | tail -1)" ge $((ALL + 2))

echo
echo "== 3. performance page: five resource tiles, details grid =="
drive_perf() {
    local tree=$1 out=$2
    ( cd "$tree" && bash tools/toolbench/build.sh "$out" desk=yes \
        app=/bin/taskmgr,melde,takt,500,performance wait=14 last=400 extra="wighalt=120" \
        plan="$tree/tools/taskmgr2/perf.txt" > "$out.log" 2>&1 )
}
drive_perf "$ROOT" "$TMPD/p" || bad "build perf"
SP="$TMPD/p/serial.txt"
num "plan targets not found" "$(cnt "$TMPD/p/plan.log" 'ZIEL NICHT GEFUNDEN')" eq 0
num "resource tiles" "$(grep -a '^taskmgr: perf sel=0' "$SP" | head -1 | sed -E 's/.* tiles=([0-9]+).*/\1/')" eq 5
num "CPU details grid has 6 values" "$(grep -a '^taskmgr: perf sel=0' "$SP" | head -1 | sed -E 's/.* stats=([0-9]+).*/\1/')" eq 6
num "Memory tile selects Memory" "$(cnt "$SP" '^taskmgr: perf sel=1')" ge 1
num "GPU tile selects GPU" "$(cnt "$SP" '^taskmgr: perf sel=4')" ge 1
num "Disk tile selects Disk" "$(cnt "$SP" '^taskmgr: perf sel=2')" ge 1
num "GPU details: 4 values (utilization, memory, frames, adapter)" "$(grep -a '^taskmgr: perf sel=4' "$SP" | head -1 | sed -E 's/.* stats=([0-9]+).*/\1/')" eq 4
python3 -I - "$SP" > "$TMPD/dash.txt" 2>&1 <<'PY'
import re, sys
txt = open(sys.argv[1], "rb").read().decode("latin1").splitlines()
sel, got = None, {}
for z in txt:
    m = re.match(r"taskmgr: perf sel=(\d+) ", z)
    if m:
        sel = int(m.group(1)); got.setdefault(sel, [])
        continue
    m = re.match(r"taskmgr: perf stat (\d+) lab=(.*) val=(.*)$", z)
    if m and sel is not None:
        got[sel].append((m.group(2), m.group(3)))
g = got.get(4, [])
zero = [v for v in g if v[1].strip() in ("0", "0 B", "0%", "0,0 %")]
util = g[0][1].strip() if g else ""
vram = g[1][1].strip() if len(g) > 1 else ""
vram_ok = vram == "--" or ("/" in vram and not vram.startswith("0 "))
sw = [v for v in got.get(0, []) if "switches" in v[0] or "Kontext" in v[0]]
ok = len(g) == 4 and not zero and util == "--" and vram_ok and bool(sw) and all(v[1].strip() == "--" for v in sw)
print("gpu=%s switches=%s" % (g, sw))
raise SystemExit(0 if ok else 1)
PY
[ $? -eq 0 ] && ok "no kernel source = --, GPU memory from /proc/gpu, never 0 ($(cat "$TMPD/dash.txt" | cut -c1-120))" || bad "dash rule: $(cat "$TMPD/dash.txt" | cut -c1-200)"

echo
echo "== 4. counter-proof: the tree before S1 fails the same plans =="
BWT="$TMPD/basewt"
if git worktree add --detach "$BWT" "$BASE" >/dev/null 2>&1; then
    mkdir -p "$BWT/tools/taskmgr2"
    cp -r tools/toolbench/. "$BWT/tools/toolbench/"
    cp tools/taskmgr2/ctx.txt tools/taskmgr2/search.txt tools/taskmgr2/perf.txt tools/taskmgr2/eff.txt tools/taskmgr2/users.txt tools/taskmgr2/del.txt "$BWT/tools/taskmgr2/"
    drive "$BWT" "$TMPD/bc" "$BWT/tools/taskmgr2/ctx.txt" || true
    drive "$BWT" "$TMPD/bs" "$BWT/tools/taskmgr2/search.txt" || true
    num "BASE $BASE: no context menu opens" "$(cnt "$TMPD/bc/serial.txt" '^taskmgr: ctx n=')" eq 0
    num "BASE $BASE: no search events" "$(cnt "$TMPD/bs/serial.txt" '^taskmgr: search n=')" eq 0
    drive_perf "$BWT" "$TMPD/bp" || true
    num "BASE $BASE: no resource tiles" "$(cnt "$TMPD/bp/serial.txt" '^taskmgr: perf sel=')" eq 0
    num "BASE $BASE: plan cannot find its targets" "$(( $(cnt "$TMPD/bc/plan.log" 'ZIEL NICHT GEFUNDEN') + $(cnt "$TMPD/bs/plan.log" 'ZIEL NICHT GEFUNDEN') ))" ge 1
else
    bad "cannot create the BASE worktree $BASE"
fi

echo
echo "== 5. S5: thread/disk counters, Efficiency mode =="
drive_eff() {
    local tree=$1 out=$2
    ( cd "$tree" && bash tools/toolbench/build.sh "$out" desk=yes \
        app=/bin/taskmgr,melde,takt,500 wait=14 last=400 extra="wighalt=120" \
        plan="$tree/tools/taskmgr2/eff.txt" > "$out.log" 2>&1 )
}
drive_eff "$ROOT" "$TMPD/e" || bad "build eff"
SE="$TMPD/e/serial.txt"
num "plan targets not found" "$(cnt "$TMPD/e/plan.log" 'ZIEL NICHT GEFUNDEN')" eq 0
num "row reports carry thr= (rows)" "$(grep -a '^taskmgr: zeile' "$SE" | grep -c ' thr=[1-9]')" ge 1
num "row reports with thr=0 for live user rows" "$(grep -a '^taskmgr: zeile' "$SE" | grep -a 'name=taskmgr' | grep -c ' thr=0 ')" eq 0
num "taskmgr reads its image: dr > 0" "$(grep -a '^taskmgr: zeile' "$SE" | grep -a 'name=taskmgr' | sed -E 's/.* dr=([0-9]+) .*/\1/' | sort -n | tail -1)" gt 0
num "menu on an app row has 3 rows" "$(grep -a '^taskmgr: ctx n=' "$SE" | head -1 | sed -E 's/.*ctx n=([0-9]+).*/\1/')" eq 3
num "menu on a system row has exactly 2 rows (no Efficiency mode)" "$(grep -a '^taskmgr: ctx n=' "$SE" | sed -n 2p | sed -E 's/.*ctx n=([0-9]+).*/\1/')" eq 2
num "exactly one Efficiency pick (act 3)" "$(cnt "$SE" '^taskmgr: ctx wahl act=3')" eq 1
EPID=$(grep -a '^taskmgr: prio pid=' "$SE" | head -1 | sed -E 's/.*pid=([0-9]+).*/\1/')
CPID=$(grep -a '^taskmgr: ctx n=' "$SE" | head -1 | sed -E 's/.* pid=([0-9]+).*/\1/')
[ -n "${EPID:-}" ] && [ "$EPID" = "$CPID" ] && ok "priority change targets the clicked row (pid $EPID)" || bad "prio pid ${EPID:-?}, clicked pid ${CPID:-?}"
num "SETPRIO accepted (rc 0)" "$(grep -a '^taskmgr: prio pid=' "$SE" | head -1 | sed -E 's/.* rc=([0-9]+).*/\1/')" eq 0
num "priority went normal -> efficiency (new=1)" "$(grep -a '^taskmgr: prio pid=' "$SE" | head -1 | sed -E 's/.* new=([0-9]+).*/\1/')" eq 1
num "old priority was normal (2)" "$(grep -a '^taskmgr: prio pid=' "$SE" | head -1 | sed -E 's/.* old=([0-9]+).*/\1/')" eq 2
num "the row reports prio=1 after the pick" "$(grep -a '^taskmgr: zeile' "$SE" | grep -a " pid=$EPID " | grep -c ' prio=1 ')" ge 1
num "the row reported prio=2 before the pick" "$(grep -a '^taskmgr: zeile' "$SE" | grep -a " pid=$EPID " | grep -c ' prio=2 ')" ge 1
if [ -n "$BWT" ] && [ -d "$BWT" ]; then
    drive_eff "$BWT" "$TMPD/be" || true
    num "BASE $BASE: rows carry no thr=" "$(grep -a '^taskmgr: zeile' "$TMPD/be/serial.txt" | grep -c ' thr=')" eq 0
    num "BASE $BASE: no priority change" "$(cnt "$TMPD/be/serial.txt" '^taskmgr: prio pid=')" eq 0
fi

echo
echo "== 6. S3/S6: Users page, Delete = End task, FPS only from /proc/frames =="
drive_users() {
    local tree=$1 out=$2
    ( cd "$tree" && bash tools/toolbench/build.sh "$out" desk=yes \
        app=/bin/taskmgr,melde,takt,500,users wait=14 last=400 extra="wighalt=120" \
        plan="$tree/tools/taskmgr2/users.txt" > "$out.log" 2>&1 )
}
drive_del() {
    local tree=$1 out=$2
    ( cd "$tree" && bash tools/toolbench/build.sh "$out" desk=yes \
        app=/bin/taskmgr,melde,takt,500 wait=14 last=400 extra="wighalt=120" \
        plan="$tree/tools/taskmgr2/del.txt" > "$out.log" 2>&1 )
}
drive_users "$ROOT" "$TMPD/u" || bad "build users"
SU="$TMPD/u/serial.txt"
num "plan targets not found" "$(cnt "$TMPD/u/plan.log" 'ZIEL NICHT GEFUNDEN')" eq 0
num "users page reports at least one owner" "$(grep -a '^taskmgr: users n=' "$SU" | head -1 | sed -E 's/.*users n=([0-9]+).*/\1/')" ge 1
num "the owner list names uid 0 (system tasks)" "$(grep -a '^taskmgr: users n=' "$SU" | head -1 | grep -c ' uid=0 ')" eq 1
num "owner rows add up to the live tasks (cnt sum >= 5)" "$(grep -a '^taskmgr: users n=' "$SU" | head -1 | grep -oE ' cnt=[0-9]+' | sed 's/.*=//' | awk '{s+=$1} END{print s+0}')" ge 5
num "no row report carries fps= without /proc/frames (shown as --)" "$(grep -a '^taskmgr: zeile' "$SU" | grep -c ' fps=')" eq 0
drive_del "$ROOT" "$TMPD/d" || bad "build del"
SD="$TMPD/d/serial.txt"
num "plan targets not found" "$(cnt "$TMPD/d/plan.log" 'ZIEL NICHT GEFUNDEN')" eq 0
DPID=$(grep -a '^taskmgr: wahl' "$SD" | tail -1 | sed -E 's/.*wahl pid=([0-9]+).*/\1/')
APID=$(grep -a '^taskmgr: frage pid=' "$SD" | head -1 | sed -E 's/.*frage pid=([0-9]+).*/\1/')
num "Delete on the chosen row asks once" "$(cnt "$SD" '^taskmgr: frage pid=')" eq 1
[ -n "${APID:-}" ] && [ "${APID:-x}" = "${DPID:-y}" ] && ok "the question is about the chosen row (pid $APID)" || bad "question pid ${APID:-?}, chosen pid ${DPID:-?}"
if [ -n "$BWT" ] && [ -d "$BWT" ]; then
    drive_del "$BWT" "$TMPD/bd" || true
    num "BASE $BASE: Delete asks nothing" "$(cnt "$TMPD/bd/serial.txt" '^taskmgr: frage pid=')" eq 0
    drive_users "$BWT" "$TMPD/bu" || true
    num "BASE $BASE: no users page report" "$(cnt "$TMPD/bu/serial.txt" '^taskmgr: users n=')" eq 0
fi

echo
if [ "$fail" -eq 0 ]; then echo "TASKMGR2: $pass passed, 0 failed"; exit 0; fi
echo "TASKMGR2: $pass passed, $fail FAILED"
exit 1
