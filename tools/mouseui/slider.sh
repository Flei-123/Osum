#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/mouseui/slider.sh -- r834: CLICK/DRAG test of the settings sliders on the design-audit machine (real pointer input through
# the QEMU monitor): mouse speed (Mouse page, mspeed) and screen-off minutes on battery (Power page, pscrb).
#
#   /root/jarvis/bin/heavy bash tools/mouseui/slider.sh
#
# For each slider: drag the handle along the track to 90 % and back to 10 %, then click the track at 50 %. After every change Settings
# reports `settings: mouse speed= ...` / `settings: power ... scrb= ...`; the test reads those lines.
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
  echo "foto sl-mouse-0"
  echo "ziehespur srectmspeed 10,90"; echo "warte 3"
  echo "foto sl-mouse-hi"
  echo "ziehespur srectmspeed 90,10"; echo "warte 3"
  echo "foto sl-mouse-lo"
  echo "ziehespur srectmspeed 10,50"; echo "warte 3"
  echo "foto sl-mouse-mid"
  echo "klickauf srecttabq"; echo "warte 3"
  echo "foto sl-power-0"
  echo "ziehespur srectpscrb 10,90"; echo "warte 3"
  echo "foto sl-power-hi"
  echo "ziehespur srectpscrb 90,10"; echo "warte 3"
  echo "foto sl-power-lo"
  echo "ziehespur srectpscrb 10,50"; echo "warte 3"
  echo "foto sl-power-mid"
} > "$DREH"
bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes halt=420 drehbuch="$DREH" > "$OUT.log" 2>&1
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
S="$OUT/serial.txt"
grep -aq 'settings: ready' "$S" && ok "window up" || bad "window up"
for r in mspeed pscrb; do
  grep -aq "settings: rect name=$r " "$S" && ok "widget $r reported" || bad "widget $r reported"
done
[ "$(grep -ac 'KERNEL STACK OVERFLOW' "$S")" = 0 ] && ok "no kernel stack overflow line" || bad "kernel stack overflow line (r837)"
grep -aq 'ziehespur .* -> KEIN' "$OUT.log" && bad "a drag had no target" || ok "every drag found its slider"
python3 -I - "$S" <<'PY' && ok "mouse speed: drag up raised it, drag down lowered it, track click set a middle value (ok=1)" || bad "mouse speed effects"
import re, sys
t = open(sys.argv[1], "rb").read().decode("latin1")
L = [tuple(int(x) for x in m.groups())
     for m in re.finditer(r"settings: mouse speed=(\d+) accel=(\d+) natural=(\d+) gestures=(\d+) ok=(\d+)", t)]
sp = [s[0] for s in L]
print("mouse speed values:", sp, "ok flags:", [s[4] for s in L])
if len(sp) < 3 or any(s[4] != 1 for s in L):
    sys.exit(1)
hi, lo = max(sp), min(sp)
if not (hi > lo and sp[-1] not in (hi, lo)):
    sys.exit(1)
PY
python3 -I - "$S" <<'PY' && ok "energy: drag up raised screen-off minutes, drag down lowered them, track click set a middle value (ok=1)" || bad "energy effects"
import re, sys
t = open(sys.argv[1], "rb").read().decode("latin1")
L = [tuple(int(x) for x in m.groups())
     for m in re.finditer(r"settings: power lidb=\d+ lida=\d+ scrb=(\d+) scra=\d+ sbyb=\d+ sbya=\d+ prfb=\d+ prfa=\d+ ok=(\d+)", t)]
sc = [s[0] for s in L]
print("scrb values:", sc, "ok flags:", [s[1] for s in L])
if len(sc) < 3 or any(s[1] != 1 for s in L):
    sys.exit(1)
hi, lo = max(sc), min(sc)
if not (hi > lo and sc[-1] not in (hi, lo)):
    sys.exit(1)
PY
c=$(grep -acE 'ABSTURZ|EXCEPTION' "$S" 2>/dev/null; true)
[ "$c" = 0 ] && ok "no crash" || bad "crash lines: $c"
echo "SLIDER-CLICK: $pass passed, $fail failed"
[ "$fail" = 0 ]
