#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/rowicons/run.sh -- r1915 start menu row icons are exact at scale 1 and 2 (32 / 64 px tiles from the 64 px bake).
# Host part: bakes vs cairosvg. Screen part: launcher search rows vs the SVG rendered at the tile size.
# Counter-proof: same boots with the 44/64 bakes removed (72 px picture only) must be clearly worse.
#   /root/jarvis/bin/heavy bash tools/rowicons/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat theme"
python3 -I tools/rowicons/check.py . | tee "$TMPD/host.txt"
grep -q 'ROWICONS-HOST: [0-9]* passed, 0 failed' "$TMPD/host.txt" && ok "host checks" || bad "host checks"
cp -a assets/apps "$TMPD/oldapps"; rm -f "$TMPD"/oldapps/*/symbol44.osym "$TMPD"/oldapps/*/symbol64.osym
mean_of() { python3 -I tools/rowicons/rows.py "$1" "$2" . | tee -a "$TMPD/rows.txt" | sed -n 's/^MEAN //p'; }
boot() { # name scale appsdir
    DESIGNBUILD="$TMPD/b-$1" APPS_DIR="$3" bash tools/design/eh6.sh "$TMPD/$1" res=1280x800 accel=kvm uiscale=$2 mode=light lang=en tafel=nein progs="$PROGS" \
        drehbuch=tools/rowicons/dreh.txt > "$TMPD/$1.log" 2>&1 < /dev/null
    rm -rf "$TMPD/b-$1"
}
for sc in 1 2; do
    boot new$sc $sc assets/apps; boot old$sc $sc "$TMPD/oldapps"
    for v in new old; do
        [ -s "$TMPD/$v$sc/01-search.ppm" ] || { bad "$v scale $sc: no picture"; continue; }
        grep -a '^panic' "$TMPD/$v$sc/serial.txt" | head -2
        echo "== $v scale $sc"; eval "m_$v=$(mean_of "$TMPD/$v$sc" $sc)"
    done
    python3 -I -c "import sys; sys.exit(0 if float('${m_new:-99}') <= 1.0 else 1)" && ok "scale $sc: row icons match the SVG at tile size (mean error ${m_new:-?} <= 1.0)" || bad "scale $sc: row icon error ${m_new:-?} > 1.0"
    python3 -I -c "import sys; sys.exit(0 if float('${m_old:-0}') >= 2.0 * float('${m_new:-99}') else 1)" && ok "scale $sc: counter-proof without the bakes is worse (${m_old:-?} >= 2 x ${m_new:-?})" || bad "scale $sc: counter-proof not worse (${m_old:-?} vs ${m_new:-?})"
done
echo "ROWICONS: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
