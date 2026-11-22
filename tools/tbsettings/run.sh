#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
shift || true
CFGS=${*:-s1 s2}
mkdir -p "$OUT"
failed=0
for cfg in $CFGS; do
  case "$cfg" in
    s1) EXTRA="" ;;
    s2) EXTRA="uiscale=2" ;;
    *) echo "unknown cfg $cfg"; exit 2 ;;
  esac
  D="$OUT/$cfg"
  mkdir -p "$D"
  SCRIPT="$D-script.txt"
  {
    echo "warte 14"
    echo "klick 24,1060"; echo "warte 3"
    echo "klickauf start_Einstellungen"; echo "warte 12"
    echo "klickauf srecttabu"; echo "warte 25"
    echo "foto page"
  } > "$SCRIPT"
  export DESIGNBUILD="${DESIGNBUILD:-$D-build}"
  # shellcheck disable=SC2086
  bash tools/design/audit.sh "$D" accel=kvm uitrace=yes halt=260 res=1920x1080 lang=de sidebar=tree $EXTRA drehbuch="$SCRIPT" > "$D.log" 2>&1
  echo "== $cfg ($EXTRA)"
  python3 -I tools/tbsettings/check.py "$D/serial.txt" "$D/page.ppm" "${cfg#s}" || failed=$((failed+1))
  rm -rf "$D-build" "$SCRIPT"
  unset DESIGNBUILD
done
echo "TBSETTINGS: $failed config(s) failed"
[ "$failed" = 0 ]
