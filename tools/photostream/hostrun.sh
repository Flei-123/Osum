#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FIRNLIB="$PWD/lib" "$FIRNC" --profile=app tools/photostream/host.fi -o "$T/host" > "$T/build.txt" 2>&1 \
    || { echo "FAIL  build host"; grep -v '^warning' "$T/build.txt" | head -20; exit 1; }
"$T/host" > "$T/out.txt"; rc=$?
grep '^FAIL' "$T/out.txt" | head -20
tail -1 "$T/out.txt"
exit $rc
