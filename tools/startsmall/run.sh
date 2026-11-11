#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT" "$OUT-build"' EXIT; fi
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
shift || true
CONFIGS=${*:-s2_720 s2_768 s1_800}
mkdir -p "$OUT"
total_fail=0
for cfg in $CONFIGS; do
  case "$cfg" in
    s2_720) RES=1280x720; SCALE=2 ;;
    s2_768) RES=1366x768; SCALE=2 ;;
    s1_800) RES=1280x800; SCALE=1 ;;
    *) echo "unknown config $cfg"; exit 2 ;;
  esac
  D="$OUT/$cfg"
  mkdir -p "$D"
  bash tools/design/audit.sh "$D" accel=kvm uitrace=yes res=$RES uiscale=$SCALE halt="${HALT:-300}" \
    drehbuch="$(pwd)/tools/startsmall/script.txt" > "$D.log" 2>&1
  python3 -I tools/startsmall/check.py "$D" "$RES" "$SCALE" || total_fail=1
done
python3 -I tools/startsmall/check.py --selftest || total_fail=1
if [ "$total_fail" = 0 ]; then echo "STARTSMALL: passed"; else echo "STARTSMALL: failed"; fi
exit "$total_fail"
