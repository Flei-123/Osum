#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/deco/run.sh -- r402 DECO: the chrome of a window, measured on a real boot.
#
#   bash tools/deco/run.sh [<outdir>]        (start it through /root/jarvis/bin/heavy)
#
# One machine (tools/design/audit.sh: shipping bar configuration, shape osum, 1280x800, KVM) is
# driven through tools/deco/deco.txt; tools/deco/check.py reads the claims out of the pictures
# and the serial log: the bar is 32 points and the buttons 46 x 32 (the `wm: fen` report), the
# title stands in the middle of the bar (equal room above and below, measured on the ink of the
# first capital), the close button turns red and the others a soft plate on hover, a held
# button is deeper, release elsewhere does nothing, release on the button acts, Alt+F4 closes
# the window with the focus.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
# every run builds in its own directory (several of these runs at once share nothing)
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes halt=190 drehbuch="$(pwd)/tools/deco/deco.txt" > "$OUT.log" 2>&1
# the same window with the shadow switch ON (the default stays OFF until the Dell has been tried)
bash tools/design/audit.sh "$OUT-schatten" accel=kvm uitrace=yes shadow=on halt=120 drehbuch="$(pwd)/tools/deco/schatten.txt" > "$OUT-schatten.log" 2>&1
python3 tools/deco/check.py "$OUT" "$OUT-schatten"
RC=$?
[ -n "${1:-}" ] || rm -rf "$OUT.log" "$OUT-build" "$OUT-schatten" "$OUT-schatten.log"
exit $RC
