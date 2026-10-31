#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
OUT=${1:-$PWD/out}
mkdir -p "$OUT"
PROFILE=$(mktemp -d)
trap 'rm -rf "$PROFILE"' EXIT
python3 -I build.py "$OUT" | while read -r name w h; do
    chromium --headless=new --no-sandbox --disable-gpu --hide-scrollbars --allow-file-access-from-files \
        --user-data-dir="$PROFILE" --force-device-scale-factor="${SCALE:-1}" --window-size="$w,$h" \
        --virtual-time-budget=2000 --screenshot="$OUT/$name.png" "file://$OUT/$name.html" > /dev/null 2>&1
    echo "$OUT/$name.png"
done
