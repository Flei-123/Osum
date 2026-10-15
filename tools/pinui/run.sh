#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/pinui/run.sh -- r824: Settings page "Users" (Konten): the PIN needs the CURRENT PIN to be changed or removed.
#
#   /root/jarvis/bin/heavy bash tools/pinui/run.sh [<outdir>]
#
# Boots the design-audit machine (tools/design/audit.sh), opens Settings, clicks the Users tab (tabe), and types into the real
# entries (rect names weg = new PIN, wej = current PIN, weh = Set PIN, wei = Remove PIN; name = 'w' + two letters of the key id).
# Sequence and expected status line (read from the serial `settings: stand ... status=[...]` lines):
#   1. no PIN yet, new PIN only          -> PIN set
#   2. new PIN, WRONG current PIN        -> Current PIN is wrong   (counter-proof: the check really happens)
#   3. new PIN, right current PIN        -> PIN set
#   4. remove, WRONG current PIN         -> Current PIN is wrong
#   5. remove, right current PIN         -> PIN removed
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT" "$OUT-build"' EXIT; fi
shift || true
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
DREH="$OUT-drehbuch.txt"
YRES=800
P1=482915; P2=735190; BAD=000999
{
  echo "warte 12"
  echo "klick 24,$((YRES-20))"; echo "warte 3"
  echo "klickauf start_Settings"; echo "warte 12"
  echo "klickauf srecttabe"; echo "warte 2"
  echo "foto 00-konten"
  # 1. first PIN
  echo "klickauf srectweg"; echo "tippe $P1"; echo "klickauf srectweh"; echo "warte 3"; echo "foto 01-set"
  # 2. change with a wrong current PIN
  echo "klickauf srectwej"; echo "tippe $BAD"; echo "klickauf srectweg"; echo "tippe $P2"; echo "klickauf srectweh"; echo "warte 3"; echo "foto 02-wrong"
  # 3. change with the right current PIN
  echo "klickauf srectwej"; echo "tippe $P1"; echo "klickauf srectweg"; echo "tippe $P2"; echo "klickauf srectweh"; echo "warte 3"; echo "foto 03-changed"
  # 4. remove with a wrong current PIN
  echo "klickauf srectwej"; echo "tippe $BAD"; echo "klickauf srectwei"; echo "warte 3"; echo "foto 04-rm-wrong"
  # 5. remove with the right current PIN (the PIN from step 3 is $P2)
  echo "klickauf srectwej"; echo "tippe $P2"; echo "klickauf srectwei"; echo "warte 3"; echo "foto 05-removed"
} > "$DREH"
bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes halt=420 drehbuch="$DREH" "$@" > "$OUT.log" 2>&1
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  OK    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }
S="$OUT/serial.txt"
grep -aq 'settings: ready' "$S" && ok "window up" || bad "window up"
for r in weg wej weh wei; do
  grep -aq "settings: rect name=$r " "$S" && ok "entry/button $r reported" || bad "entry/button $r reported"
done
grep -a 'settings: stand reiter=4' "$S" | grep -aE 'PIN' | sed 's/.*status=\[//; s/\].*//' > "$OUT.seq"
echo "  status sequence:"; sed 's/^/        /' "$OUT.seq"
want=("PIN set|PIN gesetzt" "Current PIN is wrong|Aktuelle PIN falsch" "PIN set|PIN gesetzt" "Current PIN is wrong|Aktuelle PIN falsch" "PIN removed|PIN entfernt")
names=("first PIN set without a current PIN" "change with a WRONG current PIN refused" "change with the right current PIN" "remove with a WRONG current PIN refused" "remove with the right current PIN")
mapfile -t got < "$OUT.seq"
for i in 0 1 2 3 4; do
  if [[ "${got[$i]:-}" =~ ^(${want[$i]}) ]]; then ok "${names[$i]}"; else bad "${names[$i]} (got: ${got[$i]:-none})"; fi
done
c=$(grep -acE 'ABSTURZ|EXCEPTION' "$S" 2>/dev/null; true)
[ "$c" = 0 ] && ok "no crash" || bad "crash lines: $c"
echo "PINUI: $pass passed, $fail failed"
[ "$fail" = 0 ]
