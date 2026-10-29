#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
. "$(dirname "${BASH_SOURCE[0]}")/../lib/marke-env.sh"
set -u
cd "$(dirname "$0")/../.."
. tools/bootloader/lib.sh
RUNS=${RUNS:-3}
BUS=${BUS:-ehci}
MACH=${MACH:-q35}
WANT=${WANT:-glogin: rect}
D=$(mktemp -d /root/abbilder/osbootbench.XXXXXX)
[ -n "${KEEP:-}" ] || trap 'rm -rf "$D"' EXIT
osb_prepare "$D" || { echo "OSBENCH: prepare failed"; exit 1; }
median() { tr ' ' '\n' | grep -v '^$' | sort -n | awk '{a[NR]=$1} END {print (NR ? a[int((NR+1)/2)] : -1)}'; }
declare -A all
for r in $(seq 1 "$RUNS"); do
    for loader in osboot limine; do
        img="$D/stick.img"; [ "$loader" = limine ] && img="$D/limine.img"
        osb_boot "$D" "$loader$r" "$img" "$MACH" "$BUS" 120 "$WANT"
        all[$loader]="${all[$loader]:-} $OSB_MS"
    done
done
for loader in osboot limine; do
    echo "OSBENCH: $loader $MACH/$BUS to '$WANT' ms:${all[$loader]} median $(echo "${all[$loader]}" | median)"
done
