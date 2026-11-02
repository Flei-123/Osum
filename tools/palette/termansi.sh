#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT" "$OUT-build"' EXIT
export DESIGNBUILD="$OUT-build"
for code in 41 42 43 44 47 100 101 102 103 104 107; do
    printf '\033[%sm                        \033[0m\n' "$code"
done > "$OUT/ansi.txt"
SCRIPT="$(pwd)/tools/palette/termansi.txt"
bash tools/design/eh6.sh "$OUT/dark" scheme=day mode=dark accel=kvm "xfile=/etc/ansi.txt=$OUT/ansi.txt" drehbuch="$SCRIPT" > "$OUT/dark.log" 2>&1
python3 tools/palette/termansi.py "$OUT/dark" || exit 1
bash tools/design/eh6.sh "$OUT/own" scheme=night mode=dark accel=kvm "xfile=/etc/ansi.txt=$OUT/ansi.txt" drehbuch="$SCRIPT" > "$OUT/own.log" 2>&1
if python3 tools/palette/termansi.py "$OUT/own" > "$OUT/own.out" 2>&1; then
    echo "FAIL: control scheme (palette=own) passed the terminal ANSI gate"
    exit 1
fi
echo "control (palette=own) is red as expected"
