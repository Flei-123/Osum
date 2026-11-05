#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0
fail=0
ok() { pass=$((pass + 1)); echo "OK   $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if python3 -I tools/pidkill/lint.py . > "$work/real.log"; then
    ok "tools/ has no name-based process kills ($(tail -1 "$work/real.log"))"
else
    bad "tools/ has name-based process kills"
    head -20 "$work/real.log"
fi

mkdir -p "$work/mut/tools/probe"
verb_a="p""kill"
verb_b="kill""all"

printf '%s -f some-qemu\n' "$verb_a" > "$work/mut/tools/probe/a.sh"
if python3 -I tools/pidkill/lint.py "$work/mut" > /dev/null; then
    bad "counter-proof: name-based kill with -f was not caught"
else
    ok "counter-proof: name-based kill with -f is caught"
fi

printf '%s -9 qemu-system-x86_64\n' "$verb_b" > "$work/mut/tools/probe/a.sh"
if python3 -I tools/pidkill/lint.py "$work/mut" > /dev/null; then
    bad "counter-proof: kill-by-name of all matches was not caught"
else
    ok "counter-proof: kill-by-name of all matches is caught"
fi

printf 'for p in $(pgrep -f "file=x.img"); do kill -9 "$p"; done\n' > "$work/mut/tools/probe/a.sh"
if python3 -I tools/pidkill/lint.py "$work/mut" > /dev/null; then
    bad "counter-proof: pgrep -f feeding kill was not caught"
else
    ok "counter-proof: pgrep -f feeding kill is caught"
fi

printf 'kill "$pid"; wait "$pid"\n' > "$work/mut/tools/probe/a.sh"
if python3 -I tools/pidkill/lint.py "$work/mut" > /dev/null; then
    ok "control: own-PID kill passes"
else
    bad "control: own-PID kill was flagged"
fi

mkdir -p "$work/tree/tools/lib" "$work/tree/tools/probe"
cp tools/lib/pidkill.sh "$work/tree/tools/lib/"
cat > "$work/tree/tools/probe/t.sh" <<'EOT'
. "$1/tools/lib/pidkill.sh"
sleep 300 &
outer=$!
( sleep 300 & wait ) &
group=$!
sleep 0.3
osum_kill_tree "$outer"
osum_kill_tree "$group"
sleep 0.3
if kill -0 "$outer" 2>/dev/null || kill -0 "$group" 2>/dev/null; then echo alive; else echo dead; fi
EOT
if [ "$(bash "$work/tree/tools/probe/t.sh" "$work/tree")" = dead ]; then
    ok "osum_kill_tree ends a process and its descendants"
else
    bad "osum_kill_tree left a process alive"
fi

echo "pidkill: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
