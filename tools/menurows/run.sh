#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT" "$OUT-build" "$OUT.log"' EXIT; fi
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes extra="${2:-}" halt="${HALT:-300}" drehbuch="$(pwd)/tools/menurows/dreh.txt" > "$OUT.log" 2>&1
python3 -I tools/menurows/check.py "$OUT"
