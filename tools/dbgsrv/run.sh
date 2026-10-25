#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$PWD/lib"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
python3 tools/dbgsrv/genroutes.py tools/dbgsrv/routes.fi.in "$D/routes.fi"
if cmp -s "$D/routes.fi" lib/dbgsrv/routes.fi; then echo "  OK    lib/dbgsrv/routes.fi matches generator"; else echo "  FAIL  lib/dbgsrv/routes.fi is stale"; exit 1; fi
python3 - kernel/net/wlan_knobs.fi kernel/lib/kstate.fi <<'PY' && echo "  OK    knob table: names, count and mode bits agree" || { echo "  FAIL  knob table"; exit 1; }
import re, sys
src = open(sys.argv[1]).read()
kst = open(sys.argv[2], encoding="utf-8").read()
names = [n for n in re.search(r'static mut NAMES: \[u8; (\d+)\] = "([^"]*)\\0"', src).group(2).split("\\n") if n]
size = int(re.search(r'static mut NAMES: \[u8; (\d+)\]', src).group(1))
count = int(re.search(r'fn count\(\) -> u64 \{\s*return (\d+)', src).group(1))
bits = re.findall(r'return kstate\.M_(\w+)', src)
assert len(names) == count == len(bits), (len(names), count, len(bits))
assert size == sum(len(n) + 1 for n in names) + 1, size
for n, b in zip(names, bits):
    assert n.upper() == b, (n, b)
    assert re.search(r'const M_%s: u64 = \d+' % b, kst), b
PY
if ! $FIRNC tools/dbgsrv/test.fi -o "$D/t" 2> "$D/err"; then echo "  FAIL  build"; head -20 "$D/err"; exit 1; fi
"$D/t" | tee "$D/out"
! grep -q '^  FAIL  ' "$D/out" && grep -q 'fail=0' "$D/out"
