#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
pass=0
fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  OK    %s\n' "$1"; else fail=$((fail+1)); printf '  FAIL  %s (got %s, want %s)\n' "$1" "$2" "$3"; fi
}
python3 "$HERE/bench_export.py" --out "$OUT" > "$OUT/log" 2>&1
check "export exit" "$?" "0"
field() { python3 -c "import json,sys; d=json.load(open('$OUT/bench.json')); print($1)"; }
check "schema version" "$(field "d['schema_version']")" "1"
check "geomean smp1 plausible" "$(field "0.1 < d['summary']['matrix']['smp1']['geomean'] < 10")" "True"
check "geomean smp4 plausible" "$(field "0.1 < d['summary']['matrix']['smp4']['geomean'] < 10")" "True"
check "matrix tests" "$(field "d['summary']['matrix']['smp1']['tests'] >= 40")" "True"
check "entries" "$(field "len(d['entries']) >= 60")" "True"
check "make_j4 hang" "$(field "[e['smp1']['status'] for e in d['entries'] if e['id']=='make_j4'][0]")" "hang"
check "csv rows = 2 x entries" "$(($(wc -l < "$OUT/bench.csv") - 1))" "$(field "2 * len(d['entries'])")"
check "every in_work test exists" "$(field "all(t in {e['id'] for e in d['entries']} for i in d['in_work'] for t in i['tests'])")" "True"
echo "BENCH-EXPORT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
