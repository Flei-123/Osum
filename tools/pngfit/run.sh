#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

echo "== 1. encoder + fitter on the host =="
if vendor/firn/bin/firnc -o "$D/unit" tools/pngfit/unit.fi > "$D/cc.log" 2>&1; then
    ok "lib/pngfit builds"
else
    bad "lib/pngfit does not build"; head -20 "$D/cc.log" | sed 's/^/        /'
    echo "PNGFIT: $pass passed, $fail failed"; exit 1
fi

run_case() {
    local name=$1 w=$2 h=$3 cap=$4 mode=$5 steps=$6 want=$7
    "$D/unit" "$D/$name.png" "$w" "$h" "$cap" "$mode"
    local rc=$?
    if [ "$rc" != "$want" ]; then
        bad "$name: exit $rc, expected $want"; return
    fi
    [ "$want" != 0 ] && { ok "$name: refused as expected (exit $rc)"; return; }
    local res
    if res=$(python3 -I tools/pngfit/check.py "$D/$name.png" "$w" "$h" "$cap" "$steps" 2>&1); then
        ok "$name: $res"
    else
        bad "$name: $(echo "$res" | tail -1)"
    fi
}

run_case plain 320 200 0 plain 0 0
run_case fit_keep 320 200 1000000 fit 0 0
run_case fit_half 320 200 100000 fit 1 0
run_case fit_odd 321 201 100000 fit 1 0
run_case fit_quarter 320 200 20000 fit 2 0
run_case fit_floor 320 200 2000 fit 0 1

echo "== 2. counter-proof: the old path (no fitting) overshoots the wire limit =="
plain=$(stat -c%s "$D/plain.png")
if [ "$plain" -gt 100000 ]; then
    ok "unfitted PNG is $plain bytes, over the 100000 cap (fitted: $(stat -c%s "$D/fit_half.png"))"
else
    bad "unfitted PNG only $plain bytes, the case does not exercise the cap"
fi

echo "== 3. jarvisd wiring and wire limit =="
cap=$(sed -n 's/^const RESULT_CAP: usize = \([0-9]*\)$/\1/p' kernel/app/jarvisd.fi)
limit=$(python3 -I - <<'PY'
import re
s = open('tools/bridge-server/bridge_server.py').read()
m = re.search(r'^MAX_JOB_BODY = (\d+) \* 1024$', s, re.M)
print(int(m.group(1)) * 1024 if m else 0)
PY
)
if [ -n "$cap" ] && [ "$limit" -gt 0 ] && [ $((cap + 4096)) -le "$limit" ]; then
    ok "RESULT_CAP $cap + header fits MAX_JOB_BODY $limit"
else
    bad "RESULT_CAP '$cap' does not fit MAX_JOB_BODY '$limit'"
fi
n=$(grep -c 'fit.encode_within(.*RESULT_CAP)' kernel/app/jarvisd.fi)
[ "$n" = 2 ] && ok "both screenshot paths go through encode_within" || bad "encode_within used $n times, expected 2"
grep -q 'aus.len > RESULT_CAP' kernel/app/jarvisd.fi && ok "every result is guarded against the wire limit" || bad "no generic result guard"
if vendor/firn/bin/firnc -c --profile=app -o "$D/jarvisd.o" kernel/app/jarvisd.fi > "$D/jd.log" 2>&1; then
    ok "jarvisd builds"
else
    bad "jarvisd does not build"; head -20 "$D/jd.log" | sed 's/^/        /'
fi
echo "PNGFIT: $pass passed, $fail failed"
[ "$fail" = 0 ]
