#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
mkdir -p "$OUT"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
finish() { echo "STOREOFFLINE: $pass passed, $fail failed"; [ "$fail" = 0 ]; exit $?; }

PORT_BASE=${STOREOFFLINE_PORT:-19500}
MUT="$OUT/mutant"
mkdir -p "$MUT/bin"
cp -a kernel/user "$MUT/user"
python3 -I - "$MUT/user/store.fi" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
patched = text.replace("        load_local()\n", "")
if patched == text:
    sys.exit("mutant anchor missing")
open(path, "w", encoding="utf-8").write(patched)
PY
[ $? -eq 0 ] || { bad "mutant anchor missing"; finish; }
if USRC="$MUT/user" bash tools/sync/build.sh "$MUT/bin" 0 store > "$MUT/cc.log" 2>&1; then
    ok "mutant store (no local fallback) builds"
else
    bad "mutant store does not build: $(head -5 "$MUT/cc.log")"; finish
fi

run_case() {
    local name=$1 port=$2 elf=${3:-}
    mkdir -p "$OUT/$name"
    STORE_PART=offline STORE_PORT="$port" STORE_ELF="$elf" STORE_SHOTS="$OUT/$name" bash tools/store/run.sh > "$OUT/$name.log" 2>&1
}
run_case real $PORT_BASE &
run_case mut $((PORT_BASE + 10)) "$MUT/bin/store.elf" &
wait

line=$(grep -a '^STORE: ' "$OUT/real.log" | tail -n 1)
case "$line" in
    *" 0 failed"*) ok "real store: offline checks green ($line)" ;;
    *) bad "real store: ${line:-no result}"; grep -a 'FAIL' "$OUT/real.log" | head -5 ;;
esac
line=$(grep -a '^STORE: ' "$OUT/mut.log" | tail -n 1)
case "$line" in
    *" 0 failed"*|"") bad "counter-proof: mutant without local fallback was not caught (${line:-no result})" ;;
    *) ok "counter-proof: mutant without local fallback goes red ($line)" ;;
esac
grep -aq 'FAIL  Installiert does not list hallo offline' "$OUT/mut.log" && ok "counter-proof: the mutant fails on the Installiert list" || bad "counter-proof: the mutant does not fail on the Installiert list"
finish
