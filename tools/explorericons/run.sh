#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
. tools/lib/firnenv.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { echo "  OK    $*"; pass=$((pass+1)); }
bad() { echo "  FAIL  $*"; fail=$((fail+1)); }
"$FIRNC" --profile=app tools/svg/bake.fi -o "$T/bake" > "$T/b.log" 2>&1 || { echo "baker build failed"; head -5 "$T/b.log"; exit 1; }
DIR=assets/icons/explorer
REQUIRED="folder desktop documents downloads pictures music videos drive usb pin quickaccess gallery home filter preview share rename cut copy paste delete sort view"
for n in $REQUIRED; do
  [ -f "$DIR/$n.svg" ] && grep -q "^$n	" "$DIR/index.txt" && ok "$n: svg + registry row" || bad "$n: svg or registry row missing"
done
for f in $DIR/*.svg; do
  n=$(basename "$f" .svg)
  grep -q "^$n	" "$DIR/index.txt" || bad "$n: svg without registry row"
  for s in 16 24 32 48; do
    "$T/bake" "$f" "$T/o.osym" $s; rc=$?
    if [ $rc -ne 0 ]; then bad "$n @${s}px baker exit $rc"; continue; fi
    r=$(python3 -I tools/explorericons/check.py "$f" "$T/o.osym" $s) && ok "$n @${s}px $r" || bad "$n @${s}px $r"
  done
done
mkdir -p "$T/neg"
printf '<svg viewBox="0 0 24 24"><blob/></svg>' > "$T/neg/blob.svg"
"$T/bake" "$T/neg/blob.svg" "$T/o.osym" 32; [ $? -eq 5 ] && ok "counter-proof: unsupported element exits 5" || bad "counter-proof unsupported"
printf '<svg viewBox="0 0 24 24"><rect x="1" y="1" width="8" height="8" fill="#3b82f6"/></svg>' > "$T/neg/off.svg"
"$T/bake" "$T/neg/off.svg" "$T/o.osym" 48; python3 -I tools/explorericons/check.py "$T/neg/off.svg" "$T/o.osym" 48 > /dev/null && bad "counter-proof: off-center icon accepted" || ok "counter-proof: off-center icon rejected"
printf '<svg viewBox="0 0 24 24"><rect x="0" y="0" width="24" height="24" fill="#3b82f6"/></svg>' > "$T/neg/tile.svg"
"$T/bake" "$T/neg/tile.svg" "$T/o.osym" 48; python3 -I tools/explorericons/check.py "$T/neg/tile.svg" "$T/o.osym" 48 > /dev/null && bad "counter-proof: filled tile accepted" || ok "counter-proof: filled tile rejected"
echo "explorericons: $pass OK, $fail FAIL"
[ "$fail" -eq 0 ]
