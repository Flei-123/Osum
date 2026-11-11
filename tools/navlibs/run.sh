#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/navlibs/run.sh -- gate for the Firn nav toolkit (lib/fui/nav_*) of the toolchain:
# the four Firn tests (tests/navlibs/*.fi) compile against $FIRNLIB=lib and exit 0.
#
#   bash tools/navlibs/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
. "$ROOT/tools/lib/firnenv.sh"
CC=$FIRNC
[ -x "$CC" ] || { echo "compiler missing: $CC" >&2; exit 1; }
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  PASS  $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL  $1"; }

for t in tests/navlibs/*.fi; do
    b=$(basename "$t" .fi)
    if ! "$CC" -o "$D/$b" "$t" > "$D/$b.err" 2>&1; then bad "$b: compile"; head -5 "$D/$b.err"; continue; fi
    if "$D/$b" > "$D/$b.out" 2>&1; then ok "$b: exit 0"; else bad "$b: exit $?"; tail -5 "$D/$b.out"; fi
done

echo "navlibs: PASS $pass FAIL $fail"
[ "$fail" = 0 ]
