#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$(pwd)/lib"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[ -x "$FIRNC" ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
for pair in "rootsctl:kernel/app/rootsctl.fi" "tls_main:lib/tls/tls_main.fi" "fetch:kernel/app/fetch.fi"; do
    "$FIRNC" --profile=app -o "$T/${pair%%:*}" "${pair#*:}" > "$T/b.err" 2>&1 \
        || { echo "  FAIL ${pair%%:*} does not build"; grep -v RWX "$T/b.err" | head -8; exit 1; }
done
echo "  OK   rootsctl, tls_main and fetch build against the pinned compiler"
cd "$T" && python3 -I "$OLDPWD/tools/roots/check.py" "$T/rootsctl" "$T/tls_main" "$T/fetch" 2>&1 | tail -30
