#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/repaint/idle.sh -- CPU share per task on an idle desktop with four windows open (HP-like load: Explorer, Settings, Task manager, Terminal).
#   /root/jarvis/bin/heavy bash tools/repaint/idle.sh [outdir] [extra kernel words]
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT" "$OUT-build"' EXIT; fi
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
EH_MKFS_EXTRA="/proc/" bash tools/design/eh6.sh "$OUT/o" res=${RES:-1280x800} accel=kvm tafel=nein moreprogs=term "extra=vfs lang=en termdump ${2:-}" \
    drehbuch="$(pwd)/tools/repaint/idle-windows.txt" > "$OUT/o.log" 2>&1
python3 tools/menualive/check.py table "$OUT/o/serial.txt" | head -${TOP:-12}
python3 tools/menualive/check.py cpu "$OUT/o/serial.txt" notkind:idle
