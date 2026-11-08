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
finish() { echo "STORETITLE: $pass passed, $fail failed"; [ "$fail" = 0 ]; exit $?; }

NARROW_RES=1024x768
WIDE_RES=1920x1080
PORT_BASE=${STORETITLE_PORT:-19400}

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
MUT="$OUT/mutant"
mkdir -p "$MUT/bin"
cp -a kernel/user "$MUT/user"
python3 -I - "$MUT/user/store.fi" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
start = text.index("fn ask(verb")
end = text.index("fn ask_all")
body = text[start:end]
patched = body.replace("(&s_ask_title[0 as usize]) as u64,\n", "(&s_ask_name[0 as usize]) as u64,\n")
if patched == body:
    sys.exit("mutant anchor missing")
open(path, "w", encoding="utf-8").write(text[:start] + patched + text[end:])
PY
if [ $? -ne 0 ] || cmp -s kernel/user/store.fi "$MUT/user/store.fi"; then
    bad "mutant source is identical to the real source"; finish
fi
if USRC="$MUT/user" bash tools/sync/build.sh "$MUT/bin" 0 store > "$MUT/cc.log" 2>&1; then
    ok "mutant store (dialog shows the package id) builds"
else
    bad "mutant store does not build: $(head -5 "$MUT/cc.log")"; finish
fi

run_case() {
    local name=$1 res=$2 scale=$3 port=$4 elf=${5:-}
    local dir="$OUT/$name"
    mkdir -p "$dir"
    STORE_WINDOW_ONLY=1 STORE_ASK_ONLY=1 STORE_FAST=1 STORE_RES="$res" STORE_SCALE="$scale" STORE_MODE=light \
        STORE_PORT="$port" STORE_ELF="$elf" STORE_SHOTS="$dir" bash tools/store/run.sh > "$OUT/$name.log" 2>&1
}

run_case real1 $NARROW_RES 1 $PORT_BASE &
run_case real2 $WIDE_RES 2 $((PORT_BASE + 10)) &
run_case mut1 $NARROW_RES 1 $((PORT_BASE + 20)) "$MUT/bin/store.elf" &
wait

judge() {
    local name=$1 res=$2 label=$3 expect=$4
    local shot="$OUT/$name/s4-ask-light-$res.png"
    if [ ! -f "$shot" ]; then bad "$label: no screenshot ($name)"; return; fi
    local line status
    line=$(python3 -I tools/storetitle/check.py "$shot")
    status=$?
    if [ "$expect" = green ] && [ $status -eq 0 ]; then ok "$label: $line"
    elif [ "$expect" = red ] && [ $status -ne 0 ]; then ok "$label: $line"
    else bad "$label: expected $expect ($line)"; fi
}

judge real1 $NARROW_RES "install question at scale 1 names the program by its title (Gruß), not the id" green
judge real2 $WIDE_RES "install question at scale 2 names the program by its title (Gruß), not the id" green
judge mut1 $NARROW_RES "counter-probe: old store shows the package id in the question" red
mut_line=$(python3 -I tools/storetitle/check.py "$OUT/mut1/s4-ask-light-$NARROW_RES.png" 2>/dev/null)
case "$mut_line" in
    *raw_id=True*) ok "counter-probe: the dialog line reads the lowercase id ($mut_line)" ;;
    *) bad "counter-probe: lowercase id not detected ($mut_line)" ;;
esac
for n in real1 real2; do
    line=$(grep -a '^STORE: ' "$OUT/$n.log" | tail -n 1)
    case "$line" in
        *" 0 failed"*) ok "$n: inner store window checks green ($line)" ;;
        *) bad "$n: inner store window checks not green ($line)" ;;
    esac
done
finish
