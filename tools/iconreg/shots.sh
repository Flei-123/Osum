#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
OUT=${1:?output dir}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
python3 -I tools/appreg/build.py "$ROOT" "$TMPD/reg" > "$TMPD/reg.log" 2>&1 || { cat "$TMPD/reg.log"; exit 1; }
cat > "$TMPD/script.txt" <<'EOT'
warteauf 'launcher: ready' || 120
warte 6
foto 00-bar
taste meta_l
warte 6
foto 01-start
tippe explorer
warte 3
taste ret
warte 8
foto 02-explorer
taste meta_l
warte 6
tippe terminal
warte 3
taste ret
warte 8
foto 03-terminal
taste meta_l
warte 6
tippe zeichen
warte 3
taste ret
warte 8
foto 04-charmap
EOT
EH_APPREG_DIR="$TMPD/reg" bash tools/design/eh6.sh "$TMPD/run" res=1920x1080 accel=kvm moreprogs="term charmap nedit" drehbuch="$TMPD/script.txt" > "$TMPD/run.log" 2>&1
mkdir -p "$OUT"
cp "$TMPD"/run/*.ppm "$TMPD"/run/serial.txt "$OUT/" 2>/dev/null
tail -3 "$TMPD/run.log"
