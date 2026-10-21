#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bench/mint.sh [--runs 3] [--iso <file>] [--cache <dir>] [--vcpu 3] [--mem 2048] [--out mint.json] [--keep-iso]
# r1332: Linux Mint XFCE (live ISO) in QEMU/KVM, measured like tools/bench/ref.sh (same host method) but with a desktop:
# boot -> desktop, idle RAM, idle host CPU, app start times (terminal, file manager, editor). JSON on stdout (+ --out).
# Run heavy: /root/jarvis/bin/heavy bash tools/bench/mint.sh --runs 3
# The ISO is cached in /root/abbilder/mint (override --cache); the script refuses to download when the disk is >= 88 % full.
set -uo pipefail
cd "$(dirname "$0")/../.."
RUNS=3; ISO=""; CACHE=/root/abbilder/mint; VCPU=3; MEM=2048; OUTF=""; KEEP=0
URL=https://mirrors.edge.kernel.org/linuxmint/stable/22.3
NAME=linuxmint-22.3-xfce-64bit.iso
while [ $# -gt 0 ]; do case $1 in
    --runs) RUNS=$2; shift 2;; --iso) ISO=$2; shift 2;; --cache) CACHE=$2; shift 2;; --vcpu) VCPU=$2; shift 2;;
    --mem) MEM=$2; shift 2;; --out) OUTF=$2; shift 2;; --keep-iso) KEEP=1; shift;; *) sed -n 2,7p "$0"; exit 2;; esac; done
mkdir -p "$CACHE"
[ -n "$ISO" ] || ISO=$CACHE/$NAME
if [ ! -s "$ISO" ]; then
    use=$(df --output=pcent "$CACHE" | tail -1 | tr -dc 0-9)
    [ "$use" -lt 88 ] || { echo "mint: disk ${use}% full, refusing to download" >&2; exit 3; }
    curl -sSfL -m 1800 -o "$ISO.part" "$URL/$NAME" && mv "$ISO.part" "$ISO" || { echo "mint: download failed" >&2; exit 1; }
    want=$(curl -sSf -m 30 "$URL/sha256sum.txt" | awk -v n="$NAME" '$2=="*"n||$2==n{print $1}')
    have=$(sha256sum "$ISO" | awk '{print $1}')
    [ -n "$want" ] && [ "$want" = "$have" ] || { echo "mint: sha256 mismatch" >&2; rm -f "$ISO"; exit 1; }
fi
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
res=$(python3 -I tools/bench/mintboot.py "$ISO" "$T" "$RUNS" "$VCPU" "$MEM") || { echo "mint: measurement failed" >&2; exit 1; }
echo "$res"
[ -n "$OUTF" ] && echo "$res" > "$OUTF"
[ "$KEEP" = 1 ] || true   # the cached ISO stays; remove /root/abbilder/mint by hand when done
