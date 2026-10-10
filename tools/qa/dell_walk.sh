#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/qa/dell_walk.sh -- open EVERY app of the start menu, act, photograph, judge.
#
#   /root/jarvis/bin/heavy bash tools/qa/dell_walk.sh vm   [outdir] [--apps a,b] [--res 3440x1440]
#   bash tools/qa/dell_walk.sh echt [outdir] [--device osum-a4206b26eb96] [--apps a,b] [--dry]
#   bash tools/qa/dell_walk.sh list
#
# vm   = QEMU/KVM with the stick machine (tools/design/eh6.sh), a heavy run (boots a VM).
# echt = the real Dell through the bridge (docs/QA-DELL-DURCHKLICK.md); aborts at once if the
#        device is offline, and sends nothing then.
# Output: <outdir>/protokoll.md (+ .json), <outdir>/fotos/*.png. Exit 0 = every app OK.
set -uo pipefail
cd "$(dirname "$0")/../.."
MODE=${1:-vm}
shift || true
if [ "$MODE" = list ]; then exec python3 -I tools/qa/dell_walk.py list; fi
OUT=""
if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then OUT=$1; shift; fi
if [ -z "$OUT" ]; then
    OUT=$(mktemp -d /tmp/dell-walk.XXXXXX)
    echo "outdir: $OUT (kept: it holds the protocol and the pictures)"
fi
mkdir -p "$OUT"
case "$MODE" in
    vm)   python3 tools/qa/dell_walk.py vm "$OUT" "$@" ;;
    echt) python3 tools/qa/dell_walk.py echt "$OUT" "$@" ;;
    *)    echo "usage: dell_walk.sh vm|echt|list [outdir] [options]"; exit 2 ;;
esac
RC=$?
# the build directory next to the output is only a cache; drop it unless asked to keep it
[ -n "${DELLWALK_KEEP_BUILD:-}" ] || rm -rf "$OUT-build"
exit $RC
