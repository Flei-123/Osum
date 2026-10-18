#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/textfit/run.sh [small] -- G-010 gate: no fixed (chrome) text is shortened with "..." or runs past the screen edge.
#   default: German settings (18 pages) at scale 1 (1280x800) and scale 2 (2560x1600), both must be clean.
#   small  : counter-proof, scale 2 on 1280x800 (logical 640x400, the settings content is wider than the screen);
#            the checker must FAIL there (exit 0 of this script = the checker saw it).
# Runs the audit machine (heavy). Output dirs are removed at the end.
set -uo pipefail
cd "$(dirname "$0")/../.."
D=$(mktemp -d /root/abbilder/textfit.XXXXXX)
trap 'rm -rf "$D"' EXIT
if [ "${1:-}" = small ]; then
    bash tools/design/audit.sh "$D/s" halt=900 lang=de uiscale=2 drehbuch="$PWD/tools/textfit/views-de.txt" uitrace=yes > "$D/s.log" 2>&1
    python3 -I tools/textfit/check.py "$D/s" && { echo "counter-proof FAILED: the small screen was not detected"; exit 1; }
    echo "counter-proof OK: the checker flags the small screen"; exit 0
fi
bash tools/design/audit.sh "$D/a" halt=900 lang=de uiscale=1 drehbuch="$PWD/tools/textfit/views-de.txt" uitrace=yes > "$D/a.log" 2>&1
bash tools/design/audit.sh "$D/b" halt=900 lang=de uiscale=2 res=2560x1600 drehbuch="$PWD/tools/textfit/views-de2.txt" uitrace=yes > "$D/b.log" 2>&1
python3 -I tools/textfit/check.py --selftest || exit 1
python3 -I tools/textfit/check.py "$D/a" "$D/b"
