#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$(pwd)/lib"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
rc=0
printf 'import entropy.health\nimport entropy.pool\nimport entropy.drbg\nimport entropy.seedfile\nfn main() -> i32 {\n    return 0\n}\n' > "$T/k.fi"
"$FIRNC" --profile=kernel -c "$T/k.fi" -o "$T/k.o" > "$T/k.err" 2>&1 \
    && echo "  OK   lib/entropy compiles for --profile=kernel" || { echo "  FAIL kernel profile"; head -5 "$T/k.err"; rc=1; }
"$FIRNC" --profile=app -o "$T/oracle" tools/entropy/oracle.fi > "$T/o.err" 2>&1 \
    || { echo "  FAIL oracle does not build"; grep -v RWX "$T/o.err" | head -5; exit 1; }
python3 -I tools/entropy/host_check.py "$T/oracle" || rc=1
exit $rc
