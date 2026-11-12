#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/speedcmp/common.sh
for tool in musl-gcc qemu-system-x86_64 qemu-img debugfs sfdisk python3; do
    command -v "$tool" > /dev/null 2>&1 || { echo "speedcmp: $tool missing" >&2; exit 2; }
done
W=$(mktemp -d); trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$W"' EXIT
OUT=${SPEED_OUT:-$W/out}; mkdir -p "$OUT"
CACHE=${SPEEDCMP_CACHE:-$W/cache}; mkdir -p "$CACHE"
DEBIAN_URL=${DEBIAN_URL:-https://cloud.debian.org/images/cloud/trixie/latest/debian-13-nocloud-amd64.qcow2}

[ -s "$CACHE/debian.qcow2" ] || curl -sSfL -m 900 -o "$CACHE/debian.qcow2" "$DEBIAN_URL" || { echo "speedcmp: Debian download failed" >&2; exit 1; }
build_bench "$(pwd)" "$W/speedbench" || exit 1

(while sleep "${SPEED_LOAD_INTERVAL:-10}"; do echo "$(date +%T) $(cut -d' ' -f1-3 /proc/loadavg)"; done >> "$OUT/load.log") &
echo "$(date +%T) $(cut -d' ' -f1-3 /proc/loadavg)" >> "$OUT/load.log"
bash tools/speedcmp/osum.sh "$OUT" "$W/speedbench" & OSUM_PID=$!
bash tools/speedcmp/linux.sh "$OUT" "$W/speedbench" "$CACHE/debian.qcow2" & LINUX_PID=$!
wait "$OSUM_PID"; OSUM_RC=$?
wait "$LINUX_PID"; LINUX_RC=$?
[ "$OSUM_RC" = 0 ] || { echo "speedcmp: osum side failed" >&2; exit 1; }
[ "$LINUX_RC" = 0 ] || { echo "speedcmp: linux side failed" >&2; exit 1; }
echo "$(date +%T) $(cut -d' ' -f1-3 /proc/loadavg)" >> "$OUT/load.log"
LOAD_MAX=$(awk '{ if ($2 > m) m = $2 } END { print m + 0 }' "$OUT/load.log")
LOAD_MEAN=$(awk '{ s += $2; n++ } END { printf "%.1f", s / n }' "$OUT/load.log")

NOTES="Setup: QEMU/KVM -cpu host, ${SPEED_SMP} vCPU, ${SPEED_MEM} MiB; Osum and Linux boots run concurrently (paired); Osum disk ${OSUM_DRIVE:-ahci} (words: ${SPEED_OSUM_WORDS-nosched noproc nofs}); Linux $(sed 's/linux kernel: //' "$OUT/linux-kernel.txt") disk ${LINUX_DRIVE:-ahci}. Server load (1 min) mean ${LOAD_MEAN}, max ${LOAD_MAX}. Commit $(git rev-parse --short HEAD)."
printf '%s\n' "$NOTES" > "$OUT/notes.txt"
if [ -n "${SPEED_MATRIX_ONLY_OUT:-}" ]; then exit 0; fi
python3 tools/speedcmp/matrix.py build "$OUT" --tsv "${SPEED_TSV:-docs/speed-osum-vs-linux.tsv}" --raw "${SPEED_RAW:-docs/speed-osum-vs-linux-raw.tsv}" --md "${SPEED_MD:-docs/speed-osum-vs-linux.md}" --notes "$NOTES"
