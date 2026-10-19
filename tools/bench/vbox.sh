#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bench/vbox.sh -- VirtualBox variant of the benchmark (server half; the laptop half is tools/bench/vbench.ps1).
#
#   bash tools/bench/vbox.sh script               publish vbench.ps1 (next to vbtest.ps1), prints the laptop install line
#   bash tools/bench/vbox.sh steps <image-id>     print the whole round: lock, publish, laptop lines (fetch, background run, poll), unlock
#   bash tools/bench/vbox.sh parse <bench.out> [commit] [outdir]   merge the BENCHVBOX lines of the laptop log (median) into
#                                                 <outdir>/vbox-<commit>.json (schema 1, same keys as run.sh + vbox.*)
#   bash tools/bench/vbox.sh selftest             dry run: canned laptop log through `parse` (no laptop needed)
# Rules (tools/vbox/README.md): device HOLO-LAPTOP-3 only, test VM `OrientOS-Test` only (the boss VM `OrientOS` is never touched),
# one test VM at a time (tools/vbox/run.sh lock), clean up afterwards. The laptop may be offline: then only `selftest` is possible.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
PUB=/root/jarvis/public; URLBASE=https://jarvis.fleitec.com
LIB="python3 -I $ROOT/tools/bench/lib.py"
cmd=${1:-help}; shift || true
parse() { # <bench.out> <commit> <outdir>
    local log=$1 commit=${2:-$(git rev-parse --short=8 HEAD)} out=${3:-$ROOT/bench/results} T; T=$(mktemp -d); trap 'rm -rf "$T"' RETURN
    local n=0 f
    while IFS= read -r ln; do
        n=$((n+1)); printf '%s' "${ln#BENCHVBOX }" > "$T/r$n.json"
    done < <(grep -a '^BENCHVBOX ' "$log")
    [ "$n" -gt 0 ] || { echo "vbox parse: no BENCHVBOX line in $log"; return 1; }
    mkdir -p "$out"
    $LIB merge "$out/vbox-$commit.json" "$commit" x86_64 "vbox-3vcpu" "$T"/r*.json
}
case $cmd in
  script)
    mkdir -p "$PUB/t-vbl"; cp "$ROOT/tools/bench/vbench.ps1" "$PUB/t-vbl/vbench.ps1"
    echo "LAPTOP: curl.exe -sS -f -o C:\\Users\\justi\\vbl\\vbench.ps1 $URLBASE/t-vbl/vbench.ps1" ;;
  steps)
    id=${1:?usage: steps <image-id (ODB=1 build under /root/abbilder/<id>)>}
    cat <<TXT
SERVER:  bash tools/vbox/run.sh lock w-bench          # exit 2 = taken, wait
SERVER:  bash tools/vbox/run.sh publish $id            # prints the LAPTOP fetch line (run it: stage\\o.img)
SERVER:  bash tools/bench/vbox.sh script               # prints the install line for vbench.ps1 (run it once)
SERVER:  bash tools/vbox/run.sh odbc-pack ; bash tools/vbox/run.sh odb-token   # first time only: odbinstall + odbtoken (README)
LAPTOP:  Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Users\\justi\\vbl\\vbench.ps1 -Rounds 3 -Out C:\\Users\\justi\\vbl\\bench.out'}
LAPTOP:  Get-Content C:\\Users\\justi\\vbl\\bench.out -Tail 20        # poll; ~3 min per round; lines 'BENCHVBOX {...}'
LAPTOP:  (remote_deliver the bench.out file, or paste it) -> SERVER: bash tools/bench/vbox.sh parse <bench.out> <commit>
SERVER:  bash tools/vbox/run.sh unpublish <hex> ; bash tools/vbox/run.sh unlock ; bash tools/vbox/run.sh clean $id
TXT
    ;;
  parse) parse "$@" ;;
  selftest)
    T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
    cat > "$T/bench.out" <<'LOG'
INFO: vbench start 2026-10-19T12:00:00
BENCHVBOX {"vbox.boot_agent_ms":25100,"vbox.login_to_desktop_ms":7000,"idle.cpu_pct":4,"mem.total_mb":3072.0,"mem.idle_used_mb":410.5,"vbox.host_cpu_pct":31.5}
BENCHVBOX {"vbox.boot_agent_ms":26900,"vbox.login_to_desktop_ms":6500,"idle.cpu_pct":6,"mem.total_mb":3072.0,"mem.idle_used_mb":412.5,"vbox.host_cpu_pct":29.0}
BENCHVBOX {"vbox.boot_agent_ms":25900,"vbox.login_to_desktop_ms":7200,"idle.cpu_pct":5,"mem.total_mb":3072.0,"mem.idle_used_mb":411.5,"vbox.host_cpu_pct":40.0}
INFO: vbench done 2026-10-19T12:10:00
LOG
    parse "$T/bench.out" selftest "$T" >/dev/null || { echo "FAIL parse"; exit 1; }
    python3 -I - "$T/vbox-selftest.json" <<'PY' || exit 1
import json, sys
d = json.load(open(sys.argv[1])); r = d["results"]
assert r["vbox.boot_agent_ms"] == 25900 and r["mem.idle_used_mb"] == 411.5 and r["vbox.host_cpu_pct"] == 31.5, r
assert d["host"]["runs"] == 3 and d["schema"] == 1
print("VBOX-SELFTEST: 3 rounds -> medians ok (boot_agent 25900 ms, host cpu 31.5 %)")
PY
    ;;
  *) sed -n 2,12p "$0" ;;
esac
