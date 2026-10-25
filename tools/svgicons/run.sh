#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/svgicons/run.sh -- r74: bar icons of the bundles baked from symbol.svg (72 px) at UI scale 1 and 2, compared pixel by pixel
# with the SVG rendered at the size the bar draws. Counter-proof: the same boot with the icons baked at only 32 px are measurably worse at scale 2.
#   /root/jarvis/bin/heavy bash tools/svgicons/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok() { echo "  OK    $*"; pass=$((pass+1)); }
bad() { echo "  FAIL  $*"; fail=$((fail+1)); }
LIMIT=3.0
export FIRNLIB="$ROOT/lib"
vendor/firn/bin/firnc --profile=app tools/svg/bake.fi -o "$D/bake" > "$D/bake.log" 2>&1 || { bad "baker build"; exit 1; }
mkdir -p "$D/old/assets/apps"; cp -r assets/apps/. "$D/old/assets/apps/"
for f in "$D"/old/assets/apps/*/symbol.svg; do "$D/bake" "$f" "$(dirname "$f")/symbol.osym" 32 || { bad "low-resolution bake"; exit 1; }; done
res() { python3 -I tools/svgicons/check.py "$@" | tee "$D/last.txt" | grep -v '^RESULT'; grep '^RESULT' "$D/last.txt" | tail -n 1; }
val() { sed -n "s/.*$2=\([0-9.]*\).*/\1/p" <<<"$1"; }
for s in 1 2; do
  bash tools/svgicons/shot.sh "$D/new$s" $s > "$D/new$s.log" 2>&1
  r=$(res "$D/new$s" $s "$ROOT" | tee /dev/stderr | grep '^RESULT')
  e=$(val "$r" err); z=$(val "$r" size)
  [ -n "$e" ] && python3 -I -c "import sys;sys.exit(0 if $e<=$LIMIT else 1)" && ok "scale $s: bar icons match the SVG reference at the drawn size ${z}px (err $e <= $LIMIT)" || bad "scale $s: err '$e' over $LIMIT"
  grep -aq "taskbar: sym miss" "$D/new$s/serial.txt" && bad "scale $s: a bar symbol failed to load" || ok "scale $s: every pinned symbol loaded"
  eval "NEWERR$s=$e"
done
bash tools/svgicons/shot.sh "$D/old2" 2 "$D/old/assets/apps" > "$D/old2.log" 2>&1
r=$(res "$D/old2" 2 "$ROOT" | tee /dev/stderr | grep '^RESULT')
o=$(val "$r" err)
[ -n "$o" ] && python3 -I -c "import sys;sys.exit(0 if $o>$LIMIT and $o>${NEWERR2:-0}*2 else 1)" && ok "counter-proof: 32 px bake at scale 2 is red (err $o > $LIMIT and > 2x new $NEWERR2)" || bad "counter-proof stayed green (old err '$o')"
echo "$pass/$fail OK/FAIL"; [ $fail -eq 0 ]
