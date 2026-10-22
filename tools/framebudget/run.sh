#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/framebudget/run.sh -- MON-5 gate: frame budget of the shipping desktop. 0 frames >= 32 ms in the scripted scenarios
# (start menu open/close, Settings opens, wheel scroll over Settings, window drag); judge in tools/framebudget/judge.py.
#
#   /root/jarvis/bin/heavy bash tools/framebudget/run.sh [outdir]
#
# One boot of tools/design/audit.sh (word `phases`, KVM) with tools/framebudget/scenes.txt. The judge selftest (planted 40 ms frame must be red)
# runs first and needs no VM.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT" "$OUT-build" "$OUT.log"' EXIT; fi
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
python3 -I tools/framebudget/judge.py --selftest && ok "judge selftest" || bad "judge selftest"
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes extra="phases" halt="${HALT:-900}" drehbuch="$(pwd)/tools/framebudget/scenes.txt" > "$OUT.log" 2>&1
S="$OUT/serial.txt"
if [ ! -s "$S" ]; then bad "no serial output: $(tail -n 3 "$OUT.log" | tr '\n' ' ')"; echo "FRAMEBUDGET: $pass passed, $fail failed"; exit 1; fi
python3 -I tools/framebudget/judge.py "$S" | tee "$OUT.verdict"
grep -aq '^  FAIL' "$OUT.verdict" && bad "frame budget exceeded or phases missing" || ok "frame budget held in all scenarios"
grep -aiqE 'panic|kernel fault' "$S" && bad "panic on the serial line" || ok "0 panics"
echo "FRAMEBUDGET: $pass passed, $fail failed"
[ "$fail" = 0 ]
