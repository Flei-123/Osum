#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
[ -x vendor/firn/bin/firnc ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { echo "  OK    $*"; pass=$((pass+1)); }
bad() { echo "  FAIL  $*"; fail=$((fail+1)); }
python3 -I tools/svg/gen.py | cmp -s - lib/svg/svgnames.fi && ok "svgnames.fi equals generator output" || bad "svgnames.fi stale"
printf 'profile kernel\nimport svg.svgdoc\nfn main() -> i32 {\n    return svgdoc.render(0, 0, 0, 1, 1) as i32\n}\n' > "$T/k.fi"
vendor/firn/bin/firnc --profile=kernel -c "$T/k.fi" -o "$T/k.o" > "$T/k.log" 2>&1 && ok "lib/svg compiles for profile kernel" || { bad "kernel compile"; head -5 "$T/k.log"; }
vendor/firn/bin/firnc --profile=app tools/svg/bake.fi -o "$T/bake" > "$T/b.log" 2>&1 || { bad "baker build"; head -5 "$T/b.log"; exit 1; }
for f in assets/icons/svg/*.svg; do
  for s in 24 32 48 64; do
    "$T/bake" "$f" "$T/o.osym" $s; rc=$?
    r=$(python3 -I tools/svg/cmp.py "$f" "$T/o.osym")
    set -- $r
    if [ $rc -eq 0 ] && python3 -I -c "import sys;sys.exit(0 if float('$1')<=1.0 and int('$2')<=64 and int('$3')>0 else 1)"; then ok "$(basename $f) @${s}px mean $1 worst $2"; else bad "$(basename $f) @${s}px rc=$rc $r"; fi
  done
done
printf '<svg viewBox="0 0 24 24"><path d="M2 2 L20 2 L20 20" fill="#fff"/><blob/></svg>' > "$T/bad.svg"
"$T/bake" "$T/bad.svg" "$T/o.osym" 32; [ $? -eq 5 ] && ok "counter-proof: unsupported element is reported (exit 5)" || bad "counter-proof unsupported"
printf '<svg viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" fill="#fff"/></svg>' > "$T/rect.svg"
"$T/bake" "$T/rect.svg" "$T/o.osym" 48
python3 -I - "$T/o.osym" <<'PY' && ok "rect: edges exact (full inside, 0 outside, no stray pixels)" || bad "rect pixel check"
import struct, sys
d = open(sys.argv[1], "rb").read()
a = lambda x, y: d[12 + (y * 48 + x) * 4 + 3]
assert a(24, 24) == 255 and a(2, 2) == 0 and a(8, 24) == 255 and a(7, 24) == 0 and a(39, 24) == 255 and a(40, 24) == 0
PY
echo "$pass/$fail OK/FAIL"; [ $fail -eq 0 ]
