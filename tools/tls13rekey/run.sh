#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$(pwd)/lib"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[ -x "$FIRNC" ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
"$FIRNC" --profile=app -o "$T/rekey_main" lib/tls/rekey_main.fi > "$T/b.err" 2>&1 \
    || { echo "  FAIL rekey_main does not build"; grep -v RWX "$T/b.err" | head -8; exit 1; }
echo "  OK   rekey_main builds against the pinned compiler"
cd "$T" && python3 -I "$OLDPWD/tools/tls13rekey/check.py" "$T/rekey_main" 2>&1 | tail -20
