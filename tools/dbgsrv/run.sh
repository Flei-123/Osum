#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$PWD/lib"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
python3 tools/dbgsrv/genroutes.py tools/dbgsrv/routes.fi.in "$D/routes.fi"
if cmp -s "$D/routes.fi" lib/dbgsrv/routes.fi; then echo "  OK    lib/dbgsrv/routes.fi matches generator"; else echo "  FAIL  lib/dbgsrv/routes.fi is stale"; exit 1; fi
if ! $FIRNC tools/dbgsrv/test.fi -o "$D/t" 2> "$D/err"; then echo "  FAIL  build"; head -20 "$D/err"; exit 1; fi
"$D/t" | tee "$D/out"
! grep -q '^  FAIL  ' "$D/out" && grep -q 'fail=0' "$D/out"
