#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/tls12/run.sh -- gate for the TLS 1.2 half of lib/tls (r61). Host only.
# Builds lib/tls/tls_main.fi (the OrientOS copy of Firn's tls.fi with TLS 1.2) and runs
# tools/tls12/tls12_check.py: suites x groups x signature schemes against `openssl
# s_server -tls1_2`, 512 KiB through Python's ssl, man-in-the-middle and hostile-server
# counter-checks, fuzz, real hosts when there is a route (G = non-blocking is skipped:
# OrientOS' net has no *_nb calls, see docs/TLS12.md).
# Needs: openssl, python3 with `cryptography`. Slow (~6 min): run under heavy.
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$(pwd)/lib"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[ -x "$FIRNC" ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
"$FIRNC" --profile=app -o "$T/tls_main" lib/tls/tls_main.fi > "$T/b.err" 2>&1 \
    || { echo "  FAIL tls_main does not build"; grep -v RWX "$T/b.err" | head -8; exit 1; }
echo "  OK   tls_main builds against the pinned compiler"
cd "$T" && python3 -I "$OLDPWD/tools/tls12/tls12_check.py" "$T/tls_main" 2>&1 | tail -3
