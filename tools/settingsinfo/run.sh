#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/settingsinfo/run.sh -- E1: THE SETTINGS PAGE "INFO" + EXPORT BUTTON, MEASURED.
#
#   /root/jarvis/bin/heavy bash tools/settingsinfo/run.sh [<outdir>]
#
# Boots the design-audit machine (tools/design/audit.sh) with /bin/sysinfo in the
# image, opens Settings, clicks the sidebar tile 18 (rect `tabr`), then the
# export button (rect `ibexp`). Checks (serial log):
#   1. the page exists: 18 `tab?` rects, the button rect `ibexp` is reported
#   2. the click ran /bin/sysinfo into /tmp/osum-report.txt:
#      "settings: info export rc=0 bytes=<N>" with N > 0
#   3. COUNTER-PROBE: before the click the log has NO export line
#   4. no crash lines
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT" "$OUT-build" "$OUT-drehbuch.txt" "$OUT.log"' EXIT; fi
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
DREH="$OUT-drehbuch.txt"
YRES=800
{
  echo "warte 12"
  echo "klick 24,$((YRES-20))"; echo "warte 3"
  echo "klickauf start_Settings"; echo "warte 12"
  echo "foto 00-start"
  echo "klickauf srecttabr"; echo "warte 3"
  echo "foto 01-info-page"
  echo "klickauf srectibexp"; echo "warte 6"
  echo "foto 02-exported"
} > "$DREH"
bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes halt=420 \
    progs="desktop taskbar settings launcher explorer edit sh echo ls cat theme sysinfo" \
    drehbuch="$DREH" > "$OUT.log" 2>&1
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
S="$OUT/serial.txt"
grep -aq 'settings: ready' "$S" && ok "window up" || bad "window up"
n=$(grep -ac 'settings: rect name=tab' "$S" 2>/dev/null; true)
[ "$n" -ge 18 ] && ok "18 sidebar pages reported ($n)" || bad "sidebar pages reported ($n)"
grep -aq 'settings: rect name=tabr ' "$S" && ok "tile 18 (Info) reported" || bad "tile 18 (Info) reported"
grep -aq 'settings: rect name=ibexp ' "$S" && ok "export button reported" || bad "export button reported"
l=$(grep -an 'settings: info export rc=' "$S" | head -1 | cut -d: -f1)
r=$(grep -an 'settings: rect name=ibexp ' "$S" | head -1 | cut -d: -f1)
[ -n "$l" ] && [ -n "$r" ] && [ "$r" -lt "$l" ] && ok "COUNTER-PROBE: the export line comes only AFTER the button was shown/clicked" || bad "export line order (button $r, export $l)"
b=$(grep -a 'settings: info export rc=0 bytes=' "$S" | head -1 | sed 's/.*bytes=//' | tr -dc 0-9)
[ -n "$b" ] && [ "$b" -gt 0 ] && ok "export ran: rc=0, report has $b bytes" || bad "export result (bytes='$b')"
c=$(grep -acE 'ABSTURZ|EXCEPTION' "$S" 2>/dev/null; true)
[ "$c" = 0 ] && ok "no crash" || bad "crash lines: $c"
ls "$OUT"/*.ppm >/dev/null 2>&1 && ok "pictures taken: $(ls "$OUT"/*.ppm | wc -l)" || bad "no pictures"
echo "SETTINGSINFO: $pass passed, $fail failed"
[ "$fail" = 0 ]
