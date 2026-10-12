#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/qa/redcheck-test.sh -- self-test of redcheck.sh (synthetic logs, no kernel needed).
set -uo pipefail
cd "$(dirname "$0")"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
export EXPECTED_RED="$T/base.txt"
cat > "$EXPECTED_RED" <<'B'
# test baseline
g/a | known case [0-9] | red | reason a | 2026-10-12 | t
g/a | flaky one | flaky | reason f | 2026-10-12 | t
g/s | * | flaky | whole gate flaky | 2026-10-12 | t
B
chk() { # name gate rc expected_exit expected_text   (log from stdin)
    cat > "$T/log"
    out=$(bash ./redcheck.sh "$2" "$T/log" "$3" 2>&1); rc=$?
    [[ $rc -eq $4 ]] && ok "$1: exit $rc" || bad "$1: exit $rc, expected $4"
    grep -qF -- "$5" <<<"$out" && ok "$1: output has '$5'" || { bad "$1: '$5' missing"; echo "$out" | sed 's/^/        /'; }
}
chk "green"            g/a 0 0 "0 expected red, 0 NEW red" <<<"  ok  all fine"
chk "expected only"    g/a 1 0 "expected red : known case 3" <<<$'  FAIL  known case 3 broke\n  ok x'
chk "new red"          g/a 1 1 "NEW red      : something else" <<<$'  FAIL  known case 3 broke\n  FAIL  something else'
chk "colour NEIN"      g/a 1 1 "NEW red      : fresh" <<<$'  \033[31mNEIN\033[0m fresh'
chk "exit w/o FAIL"    g/a 1 1 "crash/timeout" <<<"boot..."
chk "star: exit only"  g/s 1 0 "expected red : exit code 1" <<<"boot..."
chk "star: any FAIL"   g/s 1 0 "whole gate flaky" <<<"  FAIL  whatever"
chk "stale entry"      g/a 0 0 'FIXED?       : baseline entry "known case [0-9]"' <<<"  ok fine"
chk "flaky not stale"  g/a 0 0 "0 expected red" <<<"  ok fine"
chk "other gate"       g/zzz 1 1 "NEW red" <<<"  FAIL  known case 3"
out=$(bash ./redcheck.sh g/a "$T/log" 0 2>&1); grep -q 'flaky one' <<<"$out" && bad "flaky entry reported stale" || ok "flaky entry never reported stale"
# the real baseline parses
unset EXPECTED_RED
n=$(bash ./redcheck.sh --list | tail -n +2 | wc -l)
[[ $n -ge 8 ]] && ok "real baseline has $n entries" || bad "real baseline only $n entries"
echo; echo "REDCHECK: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
