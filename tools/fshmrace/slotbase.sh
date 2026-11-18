#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
SRC=${1:-kernel/fs/unixsock.fi}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
if grep -q 'return state + pg_at(i, p)' "$SRC"; then ok "inline page slot is relative to state"; else bad "inline page slot is an absolute address"; fi
raw=$(grep -c 'pg_at(' "$SRC")
if [ "$raw" -le 2 ]; then ok "pg_at is used only by pg_slot"; else bad "pg_at used outside pg_slot ($raw)"; fi
echo "SLOTBASE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
