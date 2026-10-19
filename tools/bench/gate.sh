#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bench/gate.sh -- performance regression gate (budgets in tools/bench/budgets.json; regression = red).
#
#   bash tools/bench/gate.sh --static                 QUICK (seconds, no VM): budgets.json is well-formed, the committed baseline
#                                                     bench/results/baseline.json is inside every budget, and the counter-proof holds:
#                                                     the same numbers worsened by 1.5x MUST violate the budgets.
#   bash tools/bench/gate.sh --result <file.json>     check an existing result file (+ counter-proof)
#   bash tools/bench/gate.sh [--image IMG] [--ui]     NIGHTLY: measure (tools/bench/measure.sh --runs 3 --portio [--ui]) on a FULL ODB=1 image
#                                                     (no --image: builds its own via tools/usbimg/build.sh, ~9 min) and check it.
# Budgets are "max" (lower is better) or "min" limits per result key, set slightly ABOVE the measured baseline. Keys the run did not
# produce are SKIPped (e.g. ui.* without --ui). Run the nightly through /root/jarvis/bin/heavy.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
LIB="python3 -I $ROOT/tools/bench/lib.py"
BUD=$ROOT/tools/bench/budgets.json
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
fin() { echo; echo "BENCH: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }

check() { # <result.json>
    local r=$1 o
    o=$($LIB gate "$r" "$BUD"); echo "$o" | grep -E "FAIL|BENCH-GATE|OK" | sed 's/^/    /'
    if echo "$o" | grep -q "BENCH-GATE: 0 violation"; then ok "result inside all budgets"; else bad "budget violated"; fi
    o=$($LIB gate "$r" "$BUD" --worsen 1.5); echo "$o" | tail -1 | sed 's/^/    counter-proof: /'
    if echo "$o" | grep -q "BENCH-GATE: 0 violation"; then bad "counter-proof: 1.5x worse result still passes (gate is blind)"; else ok "counter-proof: 1.5x worse result is RED"; fi
}

MODE=full; RES=""; IMG=""; UIARG=""
while [ $# -gt 0 ]; do
    case $1 in
        --static) MODE=static; shift ;;
        --result) MODE=result; RES=$2; shift 2 ;;
        --image) IMG=$2; shift 2 ;;
        --ui) UIARG=--ui; shift ;;
        *) sed -n 2,14p "$0"; exit 2 ;;
    esac
done

python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); assert all(('max' in v)!=('min' in v) for k,v in d.items() if not k.startswith('_'))" "$BUD" \
    && ok "budgets.json well-formed" || { bad "budgets.json malformed"; fin; }

case $MODE in
    static) [ -s bench/results/baseline.json ] && check bench/results/baseline.json || bad "bench/results/baseline.json missing" ;;
    result) check "$RES" ;;
    full)
        D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
        if [ -z "$IMG" ]; then
            ABB=${ABB:-/root/abbilder}; TOKEN=${ODB_TOKEN_FILE:-$ABB/odb.token}
            [ -s "$TOKEN" ] || bash tools/vbox/run.sh odb-token >/dev/null 2>&1
            bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
            ( export ODB=1 PARTTAB=mbr FS_BLOCKS=122880 JARVIS_DEVICE_KEY=$ABB/vm-device.key JARVIS_CONF=$ABB/justin-permissions.conf \
                     IMAGE_ID="bench-$$" ODB_TOKEN_FILE=$TOKEN
              bash tools/usbimg/build.sh "$D/img" > "$D/build.log" 2>&1 ) || { tail -10 "$D/build.log"; bad "ODB=1 image build"; fin; }
            IMG=$D/img/orientos-usb.img
        fi
        bash tools/bench/measure.sh --image "$IMG" --runs 3 --portio $UIARG --out "$D/res" --commit gate 2>&1 | tail -30
        [ -s "$D/res/gate.json" ] && check "$D/res/gate.json" || bad "no result from run.sh" ;;
esac
fin
