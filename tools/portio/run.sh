#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/portio/run.sh <outdir> [eh6 key=value ...] -- idle port-I/O measurement (QEMU trace) of the stick machine (r1181).
#   /root/jarvis/bin/heavy bash tools/portio/run.sh /tmp/pio
# Boots the desktop through tools/design/eh6.sh (drehbuch tools/portio/idle.txt) with QEMU memory-region tracing, then
# tools/portio/analyze.py prints port accesses per second (median), the top ports and the IDE command mix.
# Env: PIO_BUILD=<dir> reuses a kernel build; PIO_IDLE_FROM=<s> start of the idle window in s after the first trace line; negative = last N s (default -70).
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?usage: run.sh <outdir> [key=value ...]}; shift
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
ln -s "$(pwd)/tools/portio/qemu-wrap.sh" "$W/qemu-system-x86_64"
export PIO_REAL_PATH="$PATH" PIO_LOG="$OUT/trace.log"
export DESIGNBUILD="${PIO_BUILD:-$OUT/build}"
PATH="$W:$PATH" bash tools/design/eh6.sh "$OUT/eh" accel=kvm drehbuch=tools/portio/idle.txt "$@" > "$OUT/eh.log" 2>&1
[ -s "$PIO_LOG" ] || { echo "PORTIO: no trace"; tail -5 "$OUT/eh.log"; exit 1; }
python3 tools/portio/analyze.py "$PIO_LOG" "${PIO_IDLE_FROM:--70}" | tee "$OUT/result.txt"
rm -f "$OUT/eh/disk.img"
