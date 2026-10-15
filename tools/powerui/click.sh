#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/powerui/click.sh -- r831: CLICK test of the Power page on the design-audit machine (real pointer input through the QEMU
# monitor, not just "the widget exists" like tools/powerui/run.sh).
#
#   /root/jarvis/bin/heavy bash tools/powerui/click.sh
#
# Opens Settings from the start menu, goes to the Power tab (tabq) and picks the next entry of three choices (click, Down, Return): lid on
# battery (plidb), lid on mains (plida), power profile on battery (pprofb). After every pick Settings reports
# `settings: power lidb= lida= scrb= ... ok=`; the test reads those lines.
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
  echo "klickauf srecttabq"; echo "warte 3"
  echo "foto power-0"
  echo "klickauf srectplidb"; echo "warte 2"
  echo "taste down"; echo "warte 1"
  echo "taste ret"; echo "warte 3"
  echo "foto power-lidb"
  echo "klickauf srectplida"; echo "warte 2"
  echo "taste down"; echo "warte 1"
  echo "taste ret"; echo "warte 3"
  echo "foto power-lida"
  echo "klickauf srectpprofb"; echo "warte 2"
  echo "taste down"; echo "warte 1"
  echo "taste ret"; echo "warte 3"
  echo "foto power-profb"
} > "$DREH"
bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes halt=420 drehbuch="$DREH" > "$OUT.log" 2>&1
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
S="$OUT/serial.txt"
grep -aq 'settings: ready' "$S" && ok "window up" || bad "window up"
for r in plidb plida pprofb; do
  grep -aq "settings: rect name=$r " "$S" && ok "widget $r reported" || bad "widget $r reported"
done
python3 -I - "$S" <<'PY' && ok "three picks stored (ok=1): lidb, lida and prfb each changed, the others kept" || bad "click effects"
import re, sys
t = open(sys.argv[1], "rb").read().decode("latin1")
keys = "lidb lida scrb scra sbyb sbya prfb prfa ok".split()
L = [dict(zip(keys, (int(x) for x in m.groups())))
     for m in re.finditer(r"settings: power lidb=(\d+) lida=(\d+) scrb=(\d+) scra=(\d+) sbyb=(\d+) sbya=(\d+) prfb=(\d+) prfa=(\d+) ok=(\d+)", t)]
print("power states (lidb, lida, prfb, ok):", [(d["lidb"], d["lida"], d["prfb"], d["ok"]) for d in L])
if len(L) < 3 or any(d["ok"] != 1 for d in L):
    sys.exit(1)
L = L[-3:]
# pick 1 = lidb (first state), pick 2 = lida, pick 3 = prfb: each later state differs from the one before in its own key only
if L[1]["lida"] == L[0]["lida"] or L[2]["prfb"] == L[1]["prfb"]:
    sys.exit(1)
if L[1]["lidb"] != L[0]["lidb"] or L[2]["lidb"] != L[1]["lidb"] or L[2]["lida"] != L[1]["lida"]:
    sys.exit(1)
PY
c=$(grep -acE 'ABSTURZ|EXCEPTION' "$S" 2>/dev/null; true)
[ "$c" = 0 ] && ok "no crash" || bad "crash lines: $c"
echo "POWERUI-CLICK: $pass passed, $fail failed"
[ "$fail" = 0 ]
