#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$(pwd)/lib"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[ -x "$FIRNC" ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
rc=0
for m in packet select policy; do
    printf 'import ntp.%s\nfn main() -> i32 {\n    return 0\n}\n' "$m" > "$T/k_$m.fi"
    "$FIRNC" --profile=kernel -c "$T/k_$m.fi" -o "$T/k_$m.o" > "$T/k_$m.err" 2>&1 \
        && echo "  OK   lib/ntp/$m.fi compiles for --profile=kernel" \
        || { echo "  FAIL lib/ntp/$m.fi kernel profile"; head -5 "$T/k_$m.err"; rc=1; }
done
"$FIRNC" --profile=app -o "$T/oracle" tools/ntp/oracle.fi > "$T/o.err" 2>&1 \
    || { echo "  FAIL oracle does not build"; grep -v RWX "$T/o.err" | head -5; exit 1; }
python3 -I tools/ntp/check.py "$T/oracle" || rc=1
exit $rc
