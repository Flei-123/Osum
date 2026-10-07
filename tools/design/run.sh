#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/run.sh -- r399 DESIGN AUDIT: the measured claims, on a real boot.
#
#   bash tools/design/run.sh [<outdir>]        (start it through /root/jarvis/bin/heavy)
#
# One machine (tools/design/audit.sh: the shipping bar conf, the sea wallpaper, KVM when
# there is one) is driven through desktop, start menu, settings, explorer and a dialog
# (tools/design/views.txt); tools/design/check.py reads the claims out of the pictures
# and the serial log: the interface face, a smooth wallpaper, frosted surfaces that follow
# their rounded shape, a tinted selection with an indicator bar, vector icons at the size
# of the surface, and the cost of a composed frame.  BEFORE-numbers for the same pictures
# are in docs/DESIGN-AUDIT.md.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes halt=70 drehbuch="$(pwd)/tools/design/views.txt" > "$OUT.log" 2>&1
[ -z "${1:-}" ] || true
python3 tools/design/check.py "$OUT"
RC=$?
[ -n "${1:-}" ] || rm -f "$OUT.log"
exit $RC
