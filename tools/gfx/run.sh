#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/gfx/run.sh -- SWR graphics stack prototype on the build host (no QEMU).
#   bash tools/gfx/run.sh          checks (tools/gfx/test.fi)
#   bash tools/gfx/run.sh bench    + measurements (tools/gfx/bench.fi), prints a table
set -uo pipefail
cd "$(dirname "$0")/../.."
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { echo "fetch-firnc.sh failed"; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
rc=0
for p in test $( [ "${1:-}" = bench ] && echo bench ); do
    FIRNLIB="$PWD/lib" vendor/firn/bin/firnc --profile=app tools/gfx/$p.fi -o "$T/$p" > "$T/$p.build" 2>&1 \
        || { echo "FAIL  build $p"; grep -v '^warning' "$T/$p.build" | head -30; rc=1; continue; }
    "$T/$p"; prc=$?
    [ "$prc" = 0 ] || rc=1
done
exit $rc
