#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/tz/run.sh -- gate for the time zone database (N-004, r20). Host only.
#   1. lib/tz/zonedata.fi is exactly what tools/tz/gen.py makes from IANA tzdata
#   2. lib/tz/tz.fi compiles for the kernel profile and as host oracle
#   3. every zone x ~4M instants (grid 2024..2040 + both sides of every changeover)
#      equals Python zoneinfo; negative controls; exact changeover seconds
#      (tools/tz/check.py)
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$(pwd)/lib"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[ -x "$FIRNC" ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
rc=0
python3 tools/tz/gen.py 2>/dev/null | cmp -s - lib/tz/zonedata.fi \
    && echo "  OK   zonedata.fi equals gen.py output" || { echo "  FAIL zonedata.fi is stale (run gen.py)"; rc=1; }
printf 'import tz.tz\nfn main() -> i32 {\n    return tz.zone_count() as i32\n}\n' > "$T/k.fi"
"$FIRNC" --profile=kernel -c "$T/k.fi" -o "$T/k.o" > "$T/k.err" 2>&1 \
    && echo "  OK   lib/tz compiles for --profile=kernel" || { echo "  FAIL kernel profile"; head -5 "$T/k.err"; rc=1; }
"$FIRNC" --profile=app -o "$T/oracle" tools/tz/oracle.fi > "$T/o.err" 2>&1 \
    || { echo "  FAIL oracle does not build"; grep -v RWX "$T/o.err" | head -5; exit 1; }
python3 -I tools/tz/check.py "$T/oracle" || rc=1
exit $rc
