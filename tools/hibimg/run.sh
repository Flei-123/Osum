#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hibimg/run.sh -- host test of the S4 hibernate image format (lib/power/hibimg.fi) + kernel-profile compile check.
set -uo pipefail
cd "$(dirname "$0")/../.."
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { echo "fetch-firnc.sh failed"; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
FC="vendor/firn/bin/firnc"
echo "== 1. host test =="
if FIRNLIB="$PWD/lib" $FC --profile=app tools/hibimg/host.fi -o "$T/host" > "$T/host.build" 2>&1; then
    "$T/host" > "$T/host.out"; hrc=$?
    grep '^FAIL' "$T/host.out" | head -20
    n=$(grep -c '^ok' "$T/host.out")
    [ "$hrc" = 0 ] && ok "host.fi: $(tail -1 "$T/host.out")" || bad "host.fi: $(tail -1 "$T/host.out")"
    [ "$n" -ge 17 ] && ok "at least 17 checks ran ($n)" || bad "only $n checks ran"
else
    bad "host.fi does not build"; grep -v '^warning' "$T/host.build" | head -20
fi
echo "== 2. compiles in profile kernel =="
printf 'profile kernel\nimport power.hibimg\nexport { probe }\nfn probe() -> u64 {\n    return hibimg.crc32(0, 0)\n}\n' > "$T/k.fi"
if FIRNLIB="$PWD/lib" $FC --profile=kernel -c "$T/k.fi" -o "$T/o.o" > "$T/o.err" 2>&1; then ok "lib/power/hibimg.fi compiles in profile kernel"
else bad "does not compile in profile kernel"; grep -v '^warning' "$T/o.err" | head -10; fi
echo; echo "hibimg: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
