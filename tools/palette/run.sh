#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
python3 tools/palette/gen.py check || exit 1
python3 tools/palette/ratchet.py check || exit 1
python3 tools/palette/ratchet.py selftest || exit 1
OUT=$(mktemp -d)
trap 'rm -rf "$OUT" "$OUT-build"' EXIT
export DESIGNBUILD="$OUT-build"
VIEWS="$(pwd)/tools/palette/views.txt"
bash tools/design/audit.sh "$OUT/dark" scheme=day mode=dark accel=kvm uitrace=yes halt=300 drehbuch="$VIEWS" > "$OUT/dark.log" 2>&1
python3 tools/palette/check.py "$OUT/dark" || exit 1
bash tools/design/audit.sh "$OUT/own" scheme=night mode=dark accel=kvm uitrace=yes halt=300 drehbuch="$VIEWS" > "$OUT/own.log" 2>&1
if python3 tools/palette/check.py "$OUT/own" > "$OUT/own.out" 2>&1; then
    echo "FAIL: control scheme (palette=own) passed the palette gate"
    exit 1
fi
echo "control (palette=own) is red as expected"
bash tools/palette/termansi.sh || exit 1
bash tools/palette/screens.sh || exit 1
