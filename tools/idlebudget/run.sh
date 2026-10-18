#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/idlebudget/run.sh -- EVERY TASK OF THE IDLE DESKTOP STAYS UNDER ITS BUDGET (W-W, 18.10.2026).
#
#   bash tools/idlebudget/run.sh            # measure + table
#
# VirtualBox (z11): idle desktop, widget 45-50 %. After the netd fix (W-U) `ps` still
# showed taskbar ~36 %, starter ~23 % (+ child ~17 %), jarvismini ~11 %, boot ~25 %.
# Same method as tools/netdidle: eh6 machine, e1000 on a chatty udp link, two `ps` 30 s apart,
# then the per-task table (tools/menualive/check.py table).
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"; kill $(jobs -p) 2>/dev/null' EXIT
export DESIGNBUILD="$TMPD/build"
FPS=${FPS:-40}
qp=$((20000 + RANDOM % 20000)); hp=$((40000 + RANDOM % 20000))
python3 tools/idlebudget/flood.py "$qp" "$FPS" 150 "$hp" > "$TMPD/flood.log" 2>&1 &
fp=$!
EH_NETDEV="-netdev socket,id=n0,udp=127.0.0.1:$hp,localaddr=127.0.0.1:$qp -device e1000,netdev=n0,mac=52:54:00:aa:bb:cc" \
bash tools/design/eh6.sh "$TMPD/m" res=1280x800 accel=kvm netz=ja \
    drehbuch=tools/idlebudget/dreh.txt extra="${EXTRA:-}" > "$TMPD/m.log" 2>&1
kill $fp 2>/dev/null
[ -n "${KEEP:-}" ] && { mkdir -p "$KEEP"; cp "$TMPD/m/serial.txt" "$KEEP/serial.txt"; cp "$TMPD/m.log" "$KEEP/m.log"; }
echo "== per task (share of one core, 30 s) =="
python3 tools/menualive/check.py table "$TMPD/m/serial.txt" | head -15
python3 tools/menualive/check.py cpu "$TMPD/m/serial.txt" notkind:idle
grep -a "task\|^ *[0-9]* *[0-9]* *[a-z]* *[a-z]* " "$TMPD/m/serial.txt" | grep -a "termzeile" | tail -30 | cut -c1-120
