#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/surfaces.sh <tag> -- screenshots of the widget programs in
# light and dark mode, for the surface-token rule (base / raised / input:
# a bordered widget never has the fill of what it sits on).
#   bash tools/design/surfaces.sh before|after
set -uo pipefail
cd "$(dirname "$0")/../.."
TAG=${1:-after}
OUT=${2:-/tmp/surfaces-$TAG}
mkdir -p "$OUT" belege/design
B=tools/alltag/build.sh
for mode in light dark; do
  for prog in widgetdemo calc settings; do
    d="$OUT/$prog-$mode"
    bash $B "$d" desk=no mode=$mode warten=6 \
      extra="wigapp=/bin/$prog" progs="$prog theme sh echo ls cat" \
      > "$d.log" 2>&1
    python3 - "$d/desktop.ppm" "belege/design/$TAG-$prog-$mode.png" <<'PY'
import sys
from PIL import Image
Image.open(sys.argv[1]).convert("RGB").save(sys.argv[2])
PY
  done
done
ls -la belege/design | tail
