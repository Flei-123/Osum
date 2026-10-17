#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fps/run.sh -- W-E (17.10.2026): frame cadence (60 fps pacing) and the debug FPS overlay (settings key debug.fps).
#
#   /root/jarvis/bin/heavy bash tools/fps/run.sh [outdir] [cases]   (one boot per case, ~3 min each; cases default: all four, one after the other)
#
# Cases (tools/design/audit.sh, drehbuch tools/fps/fps.txt):
#   paced   default kernel: an active stretch is held to the 16.667 ms slot (kgui pace_wait)
#   nopace  kernel word `nopace` = the old 100 Hz tick rounds (counter-proof: cadence must NOT be 60 fps)
#   fpson   paced + /etc/mouse.conf fps=true: green text top-left of the screenshot
#   fpsoff  paced, switch off: no overlay pixels top-left (counter-proof of the switch)
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT" "$OUT"-*' EXIT; fi
mkdir -p "$OUT"
run_case() { # name, audit args...
    local n=$1; shift
    DESIGNBUILD="$OUT/build-$n" bash tools/design/audit.sh "$OUT/$n" accel=kvm uitrace=yes halt=600 drehbuch="$(pwd)/tools/fps/fps.txt" "$@" > "$OUT/$n.log" 2>&1
}
CASES=${2:-paced nopace fpson fpsoff}
for c in $CASES; do
    case $c in
        paced)  run_case paced extra=phases ;;
        nopace) run_case nopace extra="phases nopace" ;;
        fpson)  run_case fpson extra=phases fps=on ;;
        fpsoff) run_case fpsoff extra=phases ;;
    esac
done
[ "${NOJUDGE:-}" = 1 ] || python3 -I tools/fps/judge.py "$OUT"
