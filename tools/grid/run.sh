#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/grid/run.sh -- the grid geometry (lib/fui/pagegrid.fi) against an independent Python model.
#   bash tools/grid/run.sh        (seconds; no QEMU; builds tools/grid/host.fi for the build host)
set -uo pipefail
cd "$(dirname "$0")/../.."
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { echo "fetch-firnc.sh failed"; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FIRNLIB="$PWD/lib" vendor/firn/bin/firnc --profile=app tools/grid/host.fi -o "$T/host" > "$T/build.log" 2>&1 \
    || { echo "FAIL  build"; head -20 "$T/build.log"; exit 1; }
"$T/host" > "$T/rows.txt" || { echo "FAIL  host program"; exit 1; }
python3 -I tools/grid/check.py "$T/rows.txt"
