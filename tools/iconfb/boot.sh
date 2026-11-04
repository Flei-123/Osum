#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?usage: boot.sh <outdir>}
mkdir -p "$OUT"
FAIL=0
count() { local n; n=$(grep -a -c -E 'taskbar: sym (miss|fb)' "$1/serial.txt" 2>/dev/null); echo "${n:-0}"; }
run_case() {
    local name=$1 pins=$2 script
    script=$(mktemp)
    printf 'warte 25\nfoto 00-desktop\n' > "$script"
    export DESIGNBUILD="$OUT/$name-build"
    bash tools/design/audit.sh "$OUT/$name" accel=kvm halt=120 res=1280x800 uitrace=yes "pins=$pins" "drehbuch=$script" > "$OUT/$name.log" 2>&1
    rm -rf "$OUT/$name-build" "$script"
    unset DESIGNBUILD
}
run_case clean explorer,terminal,settings
run_case control certus,explorer,terminal,settings
C=$(count "$OUT/clean")
K=$(count "$OUT/control")
if [ -s "$OUT/clean/serial.txt" ] && grep -a -q 'taskbar: ' "$OUT/clean/serial.txt"; then
    [ "$C" = 0 ] && echo "  OK    desktop boot: 0 icon fallback lines" || { echo "  FAIL  desktop boot: $C icon fallback lines"; FAIL=1; }
else
    echo "  FAIL  desktop boot produced no taskbar output"; FAIL=1
fi
[ "$K" -ge 1 ] && echo "  OK    control (absent bundle) reports $K fallback line(s)" || { echo "  FAIL  control did not report the absent bundle"; FAIL=1; }
rm -rf "$OUT"/*/uitrace "$OUT"/*/disk.img
exit "$FAIL"
