#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$PWD/lib"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
echo "== regtrace: ring, formatter, parse/normalize/diff =="
if ! $FIRNC tools/regtrace/selftest.fi -o "$D/self" 2> "$D/err"; then
    echo "  FAIL  selftest.fi does not build"; head -20 "$D/err"; echo "RESULT pass=0 fail=1"; exit 1
fi
printf 0 | "$D/self" > "$D/off.txt"
printf 1 | "$D/self" > "$D/on.txt"
printf 2 | "$D/self" > "$D/overflow.txt"
printf 3 | "$D/self" > "$D/on_full.txt"
python3 -I tools/regtrace/selftest.py "$D"
