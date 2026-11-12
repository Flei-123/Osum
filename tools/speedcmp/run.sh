#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/speedcmp/common.sh
for tool in musl-gcc qemu-system-x86_64 qemu-img debugfs sfdisk python3; do
    command -v "$tool" > /dev/null 2>&1 || { echo "speedcmp: $tool missing" >&2; exit 2; }
done
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
OUT=${SPEED_OUT:-$W/out}; mkdir -p "$OUT"
CACHE=${SPEEDCMP_CACHE:-$W/cache}; mkdir -p "$CACHE"
DEBIAN_URL=${DEBIAN_URL:-https://cloud.debian.org/images/cloud/trixie/latest/debian-13-nocloud-amd64.qcow2}

[ -s "$CACHE/debian.qcow2" ] || curl -sSfL -m 900 -o "$CACHE/debian.qcow2" "$DEBIAN_URL" || { echo "speedcmp: Debian download failed" >&2; exit 1; }
build_bench "$(pwd)" "$W/speedbench" || exit 1

LOAD_BEFORE=$(cut -d' ' -f1-3 /proc/loadavg)
bash tools/speedcmp/osum.sh "$OUT" "$W/speedbench" || { echo "speedcmp: osum side failed" >&2; exit 1; }
bash tools/speedcmp/linux.sh "$OUT" "$W/speedbench" "$CACHE/debian.qcow2" || { echo "speedcmp: linux side failed" >&2; exit 1; }
LOAD_AFTER=$(cut -d' ' -f1-3 /proc/loadavg)

NOTES="Setup: QEMU/KVM -cpu host, ${SPEED_SMP} vCPU, ${SPEED_MEM} MiB; Osum disk ${OSUM_DRIVE:-ahci} (words: ${SPEED_OSUM_WORDS-nosched noproc nofs}); Linux $(cat "$OUT/linux-kernel.txt" | sed 's/linux kernel: //') disk ${LINUX_DRIVE:-ahci}, init= straight into the bench. Server load (1/5/15 min) before: ${LOAD_BEFORE}, after: ${LOAD_AFTER}. Commit $(git rev-parse --short HEAD)."
python3 -I tools/speedcmp/aggregate.py "$OUT" docs/speed-osum-vs-linux.md docs/speed-osum-vs-linux.tsv "$NOTES"
python3 -I tools/speedcmp/budget.py docs/speed-osum-vs-linux.tsv tools/speedcmp/budget.tsv
