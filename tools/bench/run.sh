#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bench/run.sh -- OrientOS benchmark runner (QEMU/KVM, host side). Boss goal: brutally lightweight and fast.
#
#   bash tools/bench/run.sh --image <orientos-usb.img of an ODB=1 build> [--runs 3] [--portio] [--ui] [--out bench/results]
#                           [--commit REV] [--token-file F] [--smp 2] [--mem 1536] [--ready REGEX] [--password PW] [--settle S] [--keep DIR]
#
# Per run (a private copy of the image, QEMU headless + ODB on a unix socket, tools/odbc/qemu.sh):
#   host.boot_login_ms     host clock from QEMU start until COM1 shows the login screen (default 'glogin: bereit')
#   host.login_to_desktop_ms   `input text` + Enter -> process list shows desktop and no glogin (as tools/odb/loop.py)
#   host.boot_agent_ms     host clock until the ODB agent answers `ping`
#   mem.*, idle.cpu_pct    `odbc info` after SETTLE seconds (guest numbers: used = total - free; idle over a 20 s sample window)
#   host.qemu_rss_mb, idle.host_cpu_pct   QEMU process RSS and CPU share of one core over the same 20 s window
#   size.kernel_kb, size.image_mb, size.esp_used_kb   from the image itself
#   guest `bench --json` (worker A's in-OS tool) when the image has it: its BENCHJSON results are merged (guest keys win)
# --portio: one extra run per round under QEMU memory-region tracing (tools/portio): idle.portio_per_s, idle.ide_cmds_per_s
#           (the trace slows the boot, so boot times come from the untraced run only)
# --ui:     tools/bench/ui.sh (audit machine, heavy): ui.input_to_picture_ms, ui.drag_frame_*, ui.menu_frame_max_ms
# Result: <out>/<commit>.json = {"schema":1,"commit","arch","results":{key:median},"units","host":{...}}; runs are medians.
# Run it through /root/jarvis/bin/heavy (full desktop boots).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
LIB="python3 -I $ROOT/tools/bench/lib.py"
ODBC="python3 -I $ROOT/tools/odbc/odbc.py -t 90"
IMG=""; RUNS=3; PORTIO=0; UI=0; OUT=$ROOT/bench/results; COMMIT=""; TOKEN=/root/abbilder/odb.token
SMP=2; MEM=1536; PW=startkennwort; READY='glogin: bereit'; SETTLE=20; KEEP=""; WIN=20
while [ $# -gt 0 ]; do
    case $1 in
        --image) IMG=$2; shift 2 ;;      --runs) RUNS=$2; shift 2 ;;
        --portio) PORTIO=1; shift ;;     --ui) UI=1; shift ;;
        --out) OUT=$2; shift 2 ;;        --commit) COMMIT=$2; shift 2 ;;
        --token-file) TOKEN=$2; shift 2 ;; --smp) SMP=$2; shift 2 ;;
        --mem) MEM=$2; shift 2 ;;        --ready) READY=$2; shift 2 ;;
        --settle) SETTLE=$2; shift 2 ;;  --password) PW=$2; shift 2 ;;  --keep) KEEP=$2; shift 2 ;;
        *) sed -n 2,22p "$0"; exit 2 ;;
    esac
done
[ -f "$IMG" ] || { echo "bench: --image <ODB=1 orientos-usb.img> required"; exit 2; }
[ -s "$TOKEN" ] || { echo "bench: token file $TOKEN missing"; exit 2; }
command -v qemu-system-x86_64 >/dev/null || { echo "bench: no qemu"; exit 2; }
[ -n "$COMMIT" ] || COMMIT=$(git rev-parse --short=8 HEAD)
T=$(mktemp -d)
cleanup() { for d in "$T"/r*; do [ -d "$d" ] && bash "$ROOT/tools/odbc/qemu.sh" stop "$d" >/dev/null 2>&1; done; rm -rf "$T"; }
trap cleanup EXIT
mkdir -p "$OUT"
now() { date +%s.%N; }

# ---- sizes (from the image: partition 1 = FAT ESP at sector 2048, osum.mb = the kernel)
sizes() { # -> json
    local k=$T/osum.mb kb=0 esp=0
    mcopy -n -i "$IMG@@$((2048*512))" ::osum.mb "$k" 2>/dev/null && kb=$(( $(stat -c%s "$k") / 1024 ))
    esp=$(mdir -i "$IMG@@$((2048*512))" -s ::/ 2>/dev/null | awk '/files/ {gsub(/ /,"",$0); sub(/.*files/,""); sub(/bytes.*/,""); b=$0} END {print int(b/1024)}')
    printf '{"size.kernel_kb":%s,"size.image_mb":%s,"size.esp_used_kb":%s}' "$kb" "$(( $(stat -c%s "$IMG") / 1048576 ))" "${esp:-0}"
}

one_run() { # <n> <traced 0|1>  -> $T/r<n>[t].json
    local n=$1 tr=$2 d=$T/r$1$([ "$2" = 1 ] && echo t) t0 ms_d ms_a pid info st
    mkdir -p "$d"; cp --reflink=auto "$IMG" "$d/disk.img" || return 1
    local port="unix:$d/odb.sock" ev=()
    if [ "$tr" = 1 ]; then
        ln -s "$ROOT/tools/portio/qemu-wrap.sh" "$d/qemu-system-x86_64"
        ev=(env "PATH=$d:$PATH" "PIO_REAL_PATH=$PATH" "PIO_LOG=$d/trace.log")
    fi
    t0=$(now)
    "${ev[@]}" bash "$ROOT/tools/odbc/qemu.sh" start "$d/disk.img" "$d" "$SMP" "$MEM" >/dev/null || { echo "  run $n: qemu start failed"; return 1; }
    pid=$(cat "$d/qemu.pid")
    ( $ODBC --port "$port" --token-file "$TOKEN" wait 240 >/dev/null 2>&1 && now > "$d/agent.t" ) &
    local aw=$!
    ms_d=$($LIB waitline "$d/com1.log" "$READY" "$t0" 240) || { echo "  run $n: '$READY' never on COM1"; tail -3 "$d/com1.log"; kill $aw 2>/dev/null; return 1; }
    wait $aw
    [ -s "$d/agent.t" ] && ms_a=$(python3 -c "import sys;print(int((float(sys.argv[1])-float(sys.argv[2]))*1000))" "$(cat "$d/agent.t")" "$t0") || ms_a=0
    # log in (as tools/odb/loop.py does) and time Enter -> desktop process up; idle numbers are taken on the logged-in desktop
    local tl; tl=$(now)
    $ODBC --port "$port" --token-file "$TOKEN" input text "$PW" >/dev/null 2>&1; $ODBC --port "$port" --token-file "$TOKEN" input key Enter >/dev/null 2>&1
    tl=$(now); local up=0 ps_
    for _ in $(seq 1 240); do
        ps_=$($ODBC --port "$port" --token-file "$TOKEN" ps 2>/dev/null)
        if echo "$ps_" | grep -qw desktop && ! echo "$ps_" | grep -qw glogin; then up=1; break; fi
        sleep 0.5
    done
    local ms_l; ms_l=$(python3 -c "import sys,time;print(int((time.time()-float(sys.argv[1]))*1000))" "$tl")
    [ "$up" = 1 ] || { echo "  run $n: no desktop after login"; ms_l=-1; }
    if [ "$tr" = 1 ]; then
        sleep 85; bash "$ROOT/tools/odbc/qemu.sh" stop "$d" >/dev/null; sleep 1
        python3 -I "$ROOT/tools/portio/analyze.py" "$d/trace.log" -70 > "$d/portio.txt" 2>&1
        $LIB portio < "$d/portio.txt" > "$d/r.json"
        [ "$(wc -c < "$d/r.json")" -gt 5 ] || { echo "  run $n (traced): no portio numbers"; return 1; }
        return 0
    fi
    sleep "$SETTLE"
    $LIB procstat "$pid" "$WIN" > "$d/proc.txt" &
    local pp=$!
    info=$($ODBC --port "$port" --token-file "$TOKEN" info --idle-ms $((WIN*1000)) 2>&1)
    wait $pp
    local rss cpu; rss=$(sed -n 's/.*rss_mb=\([0-9.]*\).*/\1/p' "$d/proc.txt"); cpu=$(sed -n 's/.*cpu_pct=\([0-9.]*\).*/\1/p' "$d/proc.txt")
    local ij; ij=$(echo "$info" | $LIB info -)
    # guest bench tool (worker A), when present
    local bj="{}"; bj=$($ODBC --port "$port" --token-file "$TOKEN" --timeout 120 exec bench --json 2>/dev/null | $LIB benchjson)
    python3 -I - "$d/r.json" "$ij" "$bj" "$ms_d" "$ms_a" "${rss:-0}" "${cpu:-0}" "$(sizes)" "$ms_l" <<'PY'
import json, sys
out, info, bj, md, ma, rss, cpu, sz, ml = sys.argv[1:10]
r = { "host.boot_login_ms": int(md), "host.boot_agent_ms": int(ma), "host.login_to_desktop_ms": int(ml), "host.qemu_rss_mb": float(rss), "idle.host_cpu_pct": float(cpu)}
r.update(json.loads(sz)); r.update(json.loads(info))
g = json.loads(bj).get("results", {})
r.update(g)                                  # guest-side numbers win for equal keys
json.dump(r, open(out, "w"))
PY
    echo "  run $n: login screen ${ms_d} ms, login->desktop ${ms_l} ms, agent ${ms_a} ms, $(echo "$ij" | tr -d '{}"')"
    bash "$ROOT/tools/odbc/qemu.sh" stop "$d" >/dev/null
}

files=()
for n in $(seq 1 "$RUNS"); do
    one_run "$n" 0 && files+=("$T/r$n/r.json")
    if [ "$PORTIO" = 1 ]; then one_run "$n" 1 && files+=("$T/r${n}t/r.json"); fi
done
if [ "$UI" = 1 ]; then
    bash "$ROOT/tools/bench/ui.sh" "$T/ui" > "$T/ui.log" 2>&1; cat "$T/ui.log" | tail -8
    [ -s "$T/ui/ui.json" ] && files+=("$T/ui/ui.json")
fi
[ ${#files[@]} -gt 0 ] || { echo "bench: no successful run"; exit 1; }
mode=qemu-full-smp$SMP; [ "$PORTIO" = 1 ] && mode=$mode+portio; [ "$UI" = 1 ] && mode=$mode+ui
$LIB merge "$OUT/$COMMIT.json" "$COMMIT" x86_64 "$mode" "${files[@]}"
[ -n "$KEEP" ] && { mkdir -p "$KEEP"; cp "$T"/r*/r.json "$T"/r*/portio.txt "$T"/r*/com1.log "$KEEP"/ 2>/dev/null; }
cat "$OUT/$COMMIT.json" | python3 -I -c "import json,sys; d=json.load(sys.stdin); [print('  %-26s %10s %s' % (k, v, d['units'].get(k,''))) for k,v in sorted(d['results'].items())]"
