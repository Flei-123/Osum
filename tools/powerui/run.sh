#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/powerui/run.sh -- r783 (L-007c): Settings page "Power" (lid, screen off, standby, profile; battery left, mains right).
#
#   /root/jarvis/bin/heavy bash tools/powerui/run.sh [<outdir>]
#
# Boots the design-audit machine (tools/design/audit.sh), opens Settings, clicks the 17th tab (rect name tabq) and operates the
# real widgets by their reported rect names: sliders pscrb/pscra (screen off, minutes), psbyb/psbya (standby), choosers
# plidb/plida (lid) and pprofb/pprofa (profile). Every change makes the program print `settings: power lidb= lida= scrb= ... ok=`.
# Checks read those lines (what the program REPORTS), plus the picture exists.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT" "$OUT-build"' EXIT; fi
shift || true
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
DREH="$OUT-drehbuch.txt"
YRES=800
{
  echo "warte 12"
  echo "klick 24,$((YRES-20))"; echo "warte 3"
  echo "klickauf start_Settings"; echo "warte 12"
  echo "klickauf srecttabq"; echo "warte 2"
  echo "foto 00-power"
  # sliders: a click in the middle of the track sets about half of the range
  echo "klickauf srectpscrb"; echo "warte 2"
  echo "klickauf srectpscra"; echo "warte 2"
  echo "klickauf srectpsbyb"; echo "warte 2"
  echo "klickauf srectpsbya"; echo "warte 2"
  # choosers: open, move down one row, take it
  echo "klickauf srectplidb"; echo "warte 2"; echo "taste down"; echo "taste enter"; echo "warte 2"
  echo "klickauf srectpprofa"; echo "warte 2"; echo "taste down"; echo "taste enter"; echo "warte 2"
  echo "foto 01-changed"
} > "$DREH"
bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes halt=420 drehbuch="$DREH" "$@" > "$OUT.log" 2>&1
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
S="$OUT/serial.txt"
grep -aq 'settings: ready' "$S" && ok "window up" || bad "window up"
for r in plidb plida pscrb pscra psbyb psbya pprofb pprofa; do
  grep -aq "settings: rect name=$r " "$S" && ok "widget $r reported" || bad "widget $r reported"
done
grep -a 'settings: power ' "$S" | uniq > "$OUT.seq"
echo "  power lines:"; sed 's/^/        /' "$OUT.seq" | tail -12
last=$(tail -1 "$OUT.seq")
f() { echo "$last" | grep -oE " $1=[0-9]+" | tail -1 | grep -oE '[0-9]+$'; }
n=$(wc -l < "$OUT.seq")
[ "$n" -ge 4 ] && ok "at least 4 stored changes ($n)" || bad "only $n stored changes"
v=$(f scrb); [ "${v:-x}" = 30 ] && ok "screen off on battery: slider click -> 30 min" || bad "screen off battery = ${v:-none} (want 30)"
v=$(f scra); [ "${v:-x}" = 30 ] && ok "screen off on mains: slider click -> 30 min" || bad "screen off mains = ${v:-none} (want 30)"
v=$(f sbyb); [ "${v:-x}" = 120 ] && ok "standby on battery: slider click -> 120 min" || bad "standby battery = ${v:-none} (want 120)"
v=$(f sbya); [ "${v:-x}" = 120 ] && ok "standby on mains: slider click -> 120 min" || bad "standby mains = ${v:-none} (want 120)"
v=$(f lidb); [ "${v:-x}" = 1 ] && ok "lid on battery: chooser row 2 (hibernate)" || bad "lid battery = ${v:-none} (want 1)"
v=$(f prfa); [ "${v:-x}" = 2 ] && ok "profile on mains: chooser row 3 (performance)" || bad "profile mains = ${v:-none} (want 2)"
v=$(f ok); [ "${v:-x}" = 1 ] && ok "the last change was stored (ok=1: bus or file)" || bad "last change not stored (ok=${v:-none})"
[ -s "$OUT/01-changed.ppm" ] || [ -s "$OUT/01-changed.png" ] && ok "picture taken" || bad "no picture"
c=$(grep -acE 'ABSTURZ|EXCEPTION' "$S" 2>/dev/null; true)
[ "$c" = 0 ] && ok "no crash" || bad "crash lines: $c"
echo "POWERUI: $pass passed, $fail failed"
[ "$fail" = 0 ]
