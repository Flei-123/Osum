#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
CYCLES=${DRIFT_CYCLES:-40}
SHOT_EVERY=${DRIFT_SHOT_EVERY:-10}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
export DESIGNBUILD="$TMPD/build"

python3 tools/drift/gen.py "$CYCLES" "$SHOT_EVERY" > "$TMPD/script.txt"
echo "== one session, $CYCLES start-menu cycles =="
bash tools/design/eh6.sh "$TMPD/run" res=1920x1080 accel=kvm drehbuch="$TMPD/script.txt" > "$TMPD/run.log" 2>&1
D="$TMPD/run"
python3 tools/drift/check.py summary "$D/fahren.log" 2.0 1.5 | tee "$TMPD/sum.txt" | sed 's/^/        /'
grep -q 'verdict=stable' "$TMPD/sum.txt" \
    && ok "every cycle answered and the latency did not drift" \
    || bad "cycles missing or latency drifted"
python3 tools/drift/check.py diff "$D" 8 580 450 1035 | tee "$TMPD/diff.txt" | sed 's/^/        /'
mn=$(sed -n 's/.*min=\([0-9]*\).*/\1/p' "$TMPD/diff.txt" | head -1)
[ "${mn:-0}" -gt 500 ] \
    && ok "typing changed the menu in every sampled cycle (min ${mn} px)" \
    || bad "the menu took no keys in some sampled cycle (min ${mn:-0} px)"
n=$(grep -acE 'panic|\*\*\* EXCEPTION|\*\*\* fault' "$D/serial.txt")
[ "$n" -eq 0 ] && ok "no panic or exception on the serial line" || bad "$n panic/exception lines"

echo "== counter-proof: the detector flags a drifting log =="
python3 - "$TMPD/doctored.log" <<'PY'
import sys
with open(sys.argv[1], "w") as f:
    for i in range(30):
        f.write("warteneu (?m)^launcher: start /apps/explorer -> da (%.2f s)\n" % (1.0 + 0.4 * i))
PY
python3 tools/drift/check.py summary "$TMPD/doctored.log" 2.0 1.5 | sed 's/^/        /'
python3 tools/drift/check.py summary "$TMPD/doctored.log" 2.0 1.5 > /dev/null \
    && bad "the detector missed a drifting log" \
    || ok "the detector flags a drifting log"

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
