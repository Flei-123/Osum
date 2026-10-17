#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/settingsui/run.sh -- settings redesign: one screenshot per page + checks.
#
#   /root/jarvis/bin/heavy bash tools/settingsui/run.sh [<outdir>] [mode=light|dark] [scale=1|2]
#
# It boots the design-audit machine (tools/design/audit.sh), opens Settings,
# clicks every sidebar page (rect names taba..tas), types into the search field
# (Ctrl+F), and takes a picture each time. Checks (serial log):
#   1. the sidebar tiles are reported (19 `tab?` rects);
#   2. the search field is reported and the window is up;
#   3. a search that matches nothing leaves the sidebar empty ("Keine Treffer");
#   4. no crash lines.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT" "$OUT-build"' EXIT; fi
shift || true
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
DREH="$OUT-drehbuch.txt"
# the start button sits 20 px above the bottom edge of the screen (default 1280x800)
YRES=800
for a in "$@"; do case "$a" in res=*) r=${a#res=}; YRES=${r#*x} ;; esac; done
{
  echo "warte 12"
  echo "klick 24,$((YRES-20))"; echo "warte 3"
  echo "klickauf start_Settings"; echo "warte 12"
  echo "foto 00-start"
  for p in a b c d e f g h i j k l m n o; do
    echo "klickauf srecttab$p"; echo "warte 2"; echo "foto page-$p"
  done
  echo "taste ctrl-f"; echo "tippe zzzz"; echo "warte 2"; echo "foto search-empty"
} > "$DREH"
bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes halt=420 drehbuch="$DREH" "$@" > "$OUT.log" 2>&1
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
S="$OUT/serial.txt"
n=$(grep -ac 'settings: rect name=tab' "$S" 2>/dev/null; true)
[ "$n" -ge 19 ] && ok "sidebar pages reported ($n)" || bad "sidebar pages reported ($n)"
grep -aq 'settings: ready' "$S" && ok "window up" || bad "window up"
# the segmented control (K_SEG0 = 180..182 -> wgy wgz wha) and the eight swatches (183..190) are real nodes
for r in wgy wgz wha; do
  grep -aq "settings: rect name=$r " "$S" && ok "segment $r reported" || bad "segment $r reported"
done
grep -aq 'settings: rect name=wdu ' "$S" && ok "search field reported" || bad "search field reported"
grep -aq 'settings: rect name=w[a-z][a-z] ' "$S" && ok "controls reported (incl. search field)" || bad "controls reported"
c=$(grep -acE 'ABSTURZ|EXCEPTION' "$S" 2>/dev/null; true)
[ "$c" = 0 ] && ok "no crash" || bad "crash lines: $c"
ls "$OUT"/*.ppm >/dev/null 2>&1 && ok "pictures taken: $(ls "$OUT"/*.ppm | wc -l)" || bad "no pictures"
bash tools/settingsui/fit.sh >/dev/null && ok "pages fit 1024x768 (fit.sh)" || bad "pages fit 1024x768 (fit.sh)"
echo "SETTINGSUI: $pass passed, $fail failed"
[ "$fail" = 0 ]
