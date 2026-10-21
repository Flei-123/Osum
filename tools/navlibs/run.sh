#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/navlibs/run.sh -- gate for the mirrored Firn nav toolkit (lib/fui/nav_*):
# 1. the four files are byte-identical to Firn's (when the Firn repository is there),
# 2. the four Firn tests (tests/navlibs/*.fi) compile against $FIRNLIB=lib and exit 0.
#
#   bash tools/navlibs/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
CC="$ROOT/vendor/firn/bin/firnc"
[ -x "$CC" ] || { echo "compiler missing: $CC" >&2; exit 1; }
FIRN="${FIRN_REPO:-/root/jarvis/projects/u_DiS4in7esMF1/firn}"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  PASS  $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL  $1"; }

for m in route layout rail palette; do
    if [ -d "$FIRN/lib/fui" ] && [ -f "$FIRN/lib/fui/nav_$m.fi" ]; then
        if cmp -s "$FIRN/lib/fui/nav_$m.fi" "lib/fui/nav_$m.fi"; then ok "nav_$m.fi equals Firn's copy"; else bad "nav_$m.fi differs from Firn's copy"; fi
    fi
done

for t in tests/navlibs/*.fi; do
    b=$(basename "$t" .fi)
    if ! "$CC" -o "$D/$b" "$t" > "$D/$b.err" 2>&1; then bad "$b: compile"; head -5 "$D/$b.err"; continue; fi
    if "$D/$b" > "$D/$b.out" 2>&1; then ok "$b: exit 0"; else bad "$b: exit $?"; tail -5 "$D/$b.out"; fi
done

for f in lib/fui/nav_*.fi; do
    if grep -aqE '^[[:space:]]*//' "$f" && ! head -1 "$f" | grep -q SPDX; then bad "$f: comment"; fi
done

echo "navlibs: PASS $pass FAIL $fail"
[ "$fail" = 0 ]
