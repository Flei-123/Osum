#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
step() {
    local what=$1; shift
    local out
    if out=$("$@" 2>&1); then ok "$what: $(echo "$out" | tail -1)"; else bad "$what: $(echo "$out" | tail -3 | tr '\n' ' ')"; fi
}
expect_fail() {
    local what=$1; shift
    if "$@" > /dev/null 2>&1; then bad "$what"; else ok "$what"; fi
}

step "no German UI literal in the converted sources" python3 tools/i18naudit/check.py scan tools/i18naudit/files.txt
step "every catalog key used in those sources exists in en and de" python3 tools/i18naudit/check.py keys tools/i18naudit/files.txt
step "en and de catalogs have the same keys" python3 tools/i18naudit/check.py parity
step "counter-proof: scanner flags a German literal" python3 tools/i18naudit/check.py probe
step "counter-proof: key check flags an unknown key" python3 tools/i18naudit/check.py keyprobe
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git show HEAD:kernel/user/mail.fi > "$tmp/mail.fi"
echo "$tmp/mail.fi" > "$tmp/list"
expect_fail "counter-proof: the unconverted mail.fi is rejected" python3 tools/i18naudit/check.py scan "$tmp/list"

echo "i18naudit: $pass ok, $fail fail"
[ "$fail" = 0 ]
