#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
rc=0
if FIRNLIB="$PWD/lib" "$FIRNC" --profile=kernel -c tools/searchrank/kcheck.fi -o "$T/kcheck.o" > "$T/kcheck.build" 2>&1; then
    echo "OK    fui.searchrank compiles in profile kernel"
else
    echo "FAIL  fui.searchrank does not compile in profile kernel"; grep -v '^warning' "$T/kcheck.build" | head -20; rc=1
fi
FIRNLIB="$PWD/lib" "$FIRNC" --profile=app tools/searchrank/host.fi -o "$T/host" > "$T/host.build" 2>&1 \
    || { echo "FAIL  build host"; grep -v '^warning' "$T/host.build" | head -20; exit 1; }
"$T/host" > "$T/host.out"; prc=$?
grep '^FAIL' "$T/host.out" | head -20
echo "searchrank: $(tail -1 "$T/host.out") (exit $prc)"
[ "$prc" = 0 ] || rc=1
checks=$(sed -n "s/^checks=\([0-9]*\) fails=.*/\1/p" "$T/host.out")
fails=$(sed -n "s/^checks=.* fails=\([0-9]*\)/\1/p" "$T/host.out")
echo "SEARCHRANK: ${checks:-0} passed, ${fails:-1} failed"
exit $rc
