#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?outdir}
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
bash tools/design/eh6.sh "$OUT" accel=kvm ${EH_EXTRA:-} drehbuch=${2:-tools/dnd/explore.txt} > "$OUT.log" 2>&1
tail -3 "$OUT.log"
