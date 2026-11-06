#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/tmpdir.sh
T=$(mktemp -d); osum_tmp_guard "" "$T"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
LIB=$PWD/tools/lib/summary.sh

probe() { # name body expected_rc expected_text [env...]
    local name=$1 body=$2 want=$3 text=$4; shift 4
    cat > "$T/p.sh" <<P
set -uo pipefail
. "$LIB"
summary_begin PROBE
trap 'summary_guard; summary_exit_status || exit 1' EXIT
trap 'exit 1' HUP INT TERM
$body
P
    env "$@" bash "$T/p.sh" > "$T/out" 2>&1; local rc=$?
    [ "$rc" -eq "$want" ] && ok "$name: rc $rc" || bad "$name: rc $rc, expected $want"
    if [ -n "$text" ]; then
        grep -qF -- "$text" "$T/out" && ok "$name: output has '$text'" || { bad "$name: '$text' missing"; sed 's/^/        /' "$T/out"; }
    else
        grep -q 'summary missing' "$T/out" && bad "$name: guard fired" || ok "$name: guard silent"
    fi
}

echo "== 1. the summary helper =="
probe "normal run"        'summary_emit 261 0 200; exit 0'                           0 "PROBE: 261 passed, 0 failed" A=1
probe "failures"          'summary_emit 250 3 200 || exit 1'                         1 "PROBE: 250 passed, 3 failed" A=1
probe "too few checks"    'summary_emit 40 0 200 || exit 1'                          1 "only 40 checks ran" A=1
probe "suppressed"        'summary_emit 261 0 200; exit 0'                           1 "summary missing" SUMMARY_SUPPRESS=1
probe "early exit 0"      'echo working; exit 0'                                     1 "summary missing" A=1
probe "unbound variable"  'echo "$nope_unset"; summary_emit 1 0'                     1 "unbound variable" A=1
probe "TERM"              'kill -TERM $$; sleep 5'                                   1 "summary missing" A=1
probe "skipped note"      'summary_note "skipped, no qemu"; exit 0'                  0 "PROBE: skipped, no qemu" A=1

echo "== 2. consumers refuse a green exit code without the summary =="
cat > "$T/req.txt" <<'R'
g/k | ^K: [0-9]+ passed, [0-9]+ failed
R
red() { SUMMARY_REQUIRED="$T/req.txt" EXPECTED_RED="$T/none.txt" bash tools/qa/redcheck.sh "$1" "$T/log" "$2" 2>&1; }
: > "$T/none.txt"
printf '  OK    a\n\nK: 5 passed, 0 failed\n' > "$T/log"
out=$(red g/k 0); rc=$?
[ "$rc" -eq 0 ] && ok "redcheck: summary present, rc 0 -> green" || bad "redcheck: green log rejected: $out"
printf '  OK    a\n' > "$T/log"
out=$(red g/k 0); rc=$?
[ "$rc" -eq 1 ] && grep -q 'summary line' <<<"$out" && ok "redcheck: summary missing, rc 0 -> NEW red" || bad "redcheck: missing summary accepted: $out"
out=$(red g/other 0); rc=$?
[ "$rc" -eq 0 ] && ok "redcheck: gate without requirement unaffected" || bad "redcheck: other gate rejected: $out"
grep -q '^k15/run | ' tools/qa/summary-required.txt && ok "k15 is registered in summary-required.txt" || bad "k15 missing in summary-required.txt"
grep -q "SUMMARY_REQUIRED_RE=(\[k15\]=" test.sh && ok "test.sh requires the k15 summary" || bad "test.sh has no k15 summary requirement"

echo "== 3. the real k15 script (no qemu on PATH) =="
FB="$T/fakebin"; mkdir -p "$FB"
for f in /usr/bin/* /bin/*; do
    case ${f##*/} in qemu*) continue ;; esac
    [ -e "$FB/${f##*/}" ] || ln -s "$f" "$FB/${f##*/}" 2>/dev/null
done
PATH="$FB" bash tools/k15/run.sh > "$T/k15a.txt" 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -q '^K15: skipped' "$T/k15a.txt" && ok "k15 without qemu: rc 0 and a summary line" || { bad "k15 without qemu: rc $rc"; tail -3 "$T/k15a.txt" | sed 's/^/        /'; }
PATH="$FB" SUMMARY_SUPPRESS=1 bash tools/k15/run.sh > "$T/k15b.txt" 2>&1; rc=$?
[ "$rc" -ne 0 ] && grep -q '^K15: 0 passed, 1 failed (summary missing' "$T/k15b.txt" && ok "k15 with the summary suppressed: rc $rc and FAIL" || { bad "k15 suppressed: rc $rc"; tail -3 "$T/k15b.txt" | sed 's/^/        /'; }
for fake in 0 1; do
    red2=$(SUMMARY_REQUIRED=tools/qa/summary-required.txt EXPECTED_RED="$T/none.txt" bash tools/qa/redcheck.sh k15/run "$T/k15b.txt" $fake 2>&1); rc=$?
    [ "$rc" -eq 1 ] && ok "redcheck on the suppressed log with rc $fake -> NEW red" || bad "redcheck accepted the suppressed log (rc $fake): $red2"
done

echo
echo "SUMMARY: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
