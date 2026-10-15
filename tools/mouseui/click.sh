#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/mouseui/click.sh -- r831: CLICK test of the Mouse page switches on the design-audit machine (real pointer clicks through
# the QEMU monitor, not just "the widget exists" like tools/mouseui/run.sh).
#
#   /root/jarvis/bin/heavy bash tools/mouseui/click.sh
#
# Opens Settings from the start menu, goes to the Mouse tab (tabp), clicks "gestures" (mges) on, off, on and "natural" (mnat) once,
# and reads what Settings REPORTS after every click (`settings: mouse speed= accel= natural= gestures= ok=`).
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT" "$OUT-build" "$OUT-drehbuch.txt"' EXIT; fi
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
DREH="$OUT-drehbuch.txt"
{
  echo "warte 12"
  echo "klick 24,780"; echo "warte 3"
  echo "klickauf start_Settings"; echo "warte 12"
  echo "klickauf srecttabp"; echo "warte 3"
  echo "foto mouse-0"
  echo "klickauf srectmges"; echo "warte 3"
  echo "foto mouse-ges-on"
  echo "klickauf srectmges"; echo "warte 3"
  echo "foto mouse-ges-off"
  echo "klickauf srectmges"; echo "warte 3"
  echo "klickauf srectmnat"; echo "warte 3"
  echo "foto mouse-nat-on"
} > "$DREH"
bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes halt=420 drehbuch="$DREH" > "$OUT.log" 2>&1
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
S="$OUT/serial.txt"
grep -aq 'settings: ready' "$S" && ok "window up" || bad "window up"
for r in mspeed maccel mnat mges; do
  grep -aq "settings: rect name=$r " "$S" && ok "widget $r reported" || bad "widget $r reported"
done
grep -aq 'klickauf srectmges -> KEIN' "$OUT.log" && bad "click on mges had no target" || ok "every click found its widget"
python3 -I - "$S" <<'PY' && ok "clicks: gestures 1, 0, 1 and natural 1, every time stored (ok=1), the other value kept" || bad "click effects"
import re, sys
t = open(sys.argv[1], "rb").read().decode("latin1")
L = [tuple(int(x) for x in m.groups())
     for m in re.finditer(r"settings: mouse speed=(\d+) accel=(\d+) natural=(\d+) gestures=(\d+) ok=(\d+)", t)]
print("states (speed, accel, natural, gestures, ok):", L)
if len(L) < 4:
    sys.exit(1)
L = L[-4:]
if any(s[4] != 1 for s in L):
    sys.exit(1)
if [s[3] for s in L] != [1, 0, 1, 1]:
    sys.exit(1)
if L[3][2] != 1 or L[2][2] != L[0][2]:
    sys.exit(1)
PY
c=$(grep -acE 'ABSTURZ|EXCEPTION' "$S" 2>/dev/null; true)
[ "$c" = 0 ] && ok "no crash" || bad "crash lines: $c"
echo "MOUSEUI-CLICK: $pass passed, $fail failed"
[ "$fail" = 0 ]
