#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/startmenu/run.sh -- r402 START MENU: the Windows 11 window, measured on a real boot.
#
#   bash tools/startmenu/run.sh [<outdir>]        (start it through /root/jarvis/bin/heavy)
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
# every run builds in its own directory (several of these runs at once share nothing)
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes halt=280 drehbuch="$(pwd)/tools/startmenu/menu.txt" > "$OUT.log" 2>&1
python3 tools/startmenu/check.py "$OUT"
RC=$?
[ -n "${1:-}" ] || rm -rf "$OUT.log" "$OUT-build"
exit $RC
