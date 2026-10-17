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
# X5: the installer entry on the stick vs. on an installed disk (marker /etc/installed): same search, two machines
IN=$OUT-inst; mkdir -p "$IN-etc"; printf '1\n' > "$IN-etc/installed"
DESIGNBUILD="$OUT-build-i1" bash tools/design/audit.sh "$IN-stick" accel=kvm uitrace=yes halt=120 progs="desktop taskbar settings launcher explorer edit sh echo ls cat theme installer" drehbuch="$(pwd)/tools/startmenu/installed.txt" > "$OUT-i1.log" 2>&1
ETCFILES="$IN-etc" DESIGNBUILD="$OUT-build-i2" bash tools/design/audit.sh "$IN-disk" accel=kvm uitrace=yes halt=120 progs="desktop taskbar settings launcher explorer edit sh echo ls cat theme installer" drehbuch="$(pwd)/tools/startmenu/installed.txt" > "$OUT-i2.log" 2>&1
python3 tools/startmenu/instcheck.py "$IN-stick" "$IN-disk" || RC=1
rm -rf "$IN-stick" "$IN-disk" "$IN-etc" "$OUT-build-i1" "$OUT-build-i2" "$OUT-i1.log" "$OUT-i2.log"
[ -n "${1:-}" ] || rm -rf "$OUT.log" "$OUT-build"
exit $RC
