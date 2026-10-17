#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/latency/run.sh -- input -> picture latency of the desktop (W-J, boss: "every interaction feels slow").
#
#   /root/jarvis/bin/heavy bash tools/latency/run.sh [outdir]
#
# Two boots of the shipping configuration (tools/design/audit.sh, word `phases`) with the workload tools/latency/latency.txt:
# the new loop (default) must keep the mean input -> picture time <= 16 ms and no gap/frame > 33 ms in the pointer phases;
# the same image with the word `nolatfix` (old 10-20 ms loop) is the counter-proof and must be RED (> 16 ms).
# What is measured (kernel clocks, `wm: lat` line): wait of a packet before the input poll + poll -> frame on the card. The host's
# own delay (QEMU, display) is not part of it.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT" "$OUT-build" "$OUT-build2" "$OUT".log*' EXIT; fi
mkdir -p "$OUT"
bad=0
run() { # <name> <extra words> <judge args>
    local nm=$1 extra=$2 jargs=$3
    export DESIGNBUILD="$OUT-build-$nm"
    bash tools/design/audit.sh "$OUT/$nm" accel=kvm uitrace=yes extra="phases wmdauer $extra" halt="${HALT:-700}" drehbuch="$(pwd)/tools/latency/latency.txt" > "$OUT.log-$nm" 2>&1
    echo "== $nm ($extra)"
    python3 -I tools/latency/judge.py "$OUT/$nm/serial.txt" $jargs || bad=1
    rm -rf "$DESIGNBUILD"
}
run new "" ""
run old "nolatfix" "--expect-red"
exit $bad
