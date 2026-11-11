#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/tokens/run.sh -- the design tokens (lib/fui/tokens.fi) against an independent Python model.
#   bash tools/tokens/run.sh        (seconds; no QEMU; builds tools/tokens/host.fi for the build host)
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FIRNLIB="$PWD/lib" "$FIRNC" --profile=app tools/tokens/host.fi -o "$T/host" > "$T/build.log" 2>&1 \
    || { echo "FAIL  build"; head -20 "$T/build.log"; exit 1; }
"$T/host" > "$T/rows.txt" || { echo "FAIL  host program"; exit 1; }
python3 -I tools/tokens/check.py "$T/rows.txt"
