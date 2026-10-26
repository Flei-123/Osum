#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
python3 -I -m unittest discover -s tools/marke -p 'test_*.py' -v 2>&1 | tail -40
rc=${PIPESTATUS[0]}
[ "$rc" -eq 0 ] && echo "MARKE: all passed" || echo "MARKE: FAILED"
exit "$rc"
