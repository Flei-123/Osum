#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/marke-env.sh"
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
IMG=${1:?usage: run.sh <ODB=1 "${MARKE_DATEI}-usb".img> [settle_s]}
SETTLE=${2:-25}
TOKEN=${ODB_TOKEN_FILE:-/root/abbilder/odb.token}
MAX_PX=${SHOTFID_MAX_PX:-3000}
MAX_MEAN=${SHOTFID_MAX_MEAN:-40}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d)
cleanup() { bash "$ROOT/tools/odbc/qemu.sh" stop "$D" >/dev/null 2>&1; rm -rf "$D"; }
trap cleanup EXIT
cp --reflink=auto "$IMG" "$D/disk.img" || exit 2
QEMU_DRIVE=ahci QEMU_EXTRA="-monitor unix:$D/mon.sock,server=on,wait=off" \
    bash tools/odbc/qemu.sh start "$D/disk.img" "$D" 2 1536 >/dev/null || { echo "SHOTFID: qemu did not start"; exit 1; }
PORT="unix:$D/odb.sock"
odbc() { python3 -I tools/odbc/odbc.py --port "$PORT" --token-file "$TOKEN" "$@"; }
echo "== 1. screen of the guest, inside (SYS_OSUM_SHOT) vs outside (QEMU screendump) =="
odbc wait 240 >/dev/null 2>&1 || { bad "agent never answered"; echo "SHOTFID: $pass passed, $fail failed"; exit 1; }
sleep "$SETTLE"
python3 -I tools/gfx/screenshot.py "$D/mon.sock" "$D/before.ppm" 25 >"$D/s1.log" 2>&1 && ok "outside shot before" || bad "no outside shot"
odbc shot "$D/in.png" --scale 100 >"$D/in.log" 2>&1 && ok "inside shot 100 percent ($(stat -c%s "$D/in.png") bytes)" || { bad "inside shot failed"; tail -2 "$D/in.log"; }
python3 -I tools/gfx/screenshot.py "$D/mon.sock" "$D/after.ppm" 25 >"$D/s2.log" 2>&1 && ok "outside shot after" || bad "no outside shot after"
if [ -s "$D/in.png" ] && [ -s "$D/before.ppm" ]; then
    r1=$(python3 -I tools/shotfid/compare.py "$D/in.png" "$D/before.ppm" "$MAX_PX" "$MAX_MEAN" 2>&1); c1=$?
    r2=$(python3 -I tools/shotfid/compare.py "$D/in.png" "$D/after.ppm" "$MAX_PX" "$MAX_MEAN" 2>&1); c2=$?
    n=$(python3 -I tools/shotfid/compare.py "$D/before.ppm" "$D/after.ppm" 100000000 255 2>&1)
    echo "        inside vs before: $(echo "$r1" | tail -1)"
    echo "        inside vs after:  $(echo "$r2" | tail -1)"
    echo "        before vs after:  $(echo "$n" | tail -1)"
    if [ "$c1" = 0 ] || [ "$c2" = 0 ]; then ok "inside image equals the card image (channel order, pitch, size)"; else bad "inside image differs from the card image"; fi
fi
echo "SHOTFID: $pass passed, $fail failed"
[ "$fail" = 0 ]
