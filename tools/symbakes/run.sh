#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/symbakes/run.sh -- r1920: every consumer of a bundle symbol picks the 44/64 px bake (symvar.pick).
# 1 host: bundles incl. pakete/jarvismini carry exact bakes (tools/rowicons/check.py) + wiring audit with counter-proof
# 2 screen: task manager program row (launcher icon) vs the SVG at the tile size, scale 1 and 2, counter-proof without bakes
# the bar draws 36 / 72 px (exact 2:1 / 1:1 from the 72 px picture, tools/svgicons gate); symvar.pick only changes other sizes
#   /root/jarvis/bin/heavy bash tools/symbakes/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
python3 -I tools/rowicons/check.py . | tee "$TMPD/host.txt"
grep -q 'ROWICONS-HOST: [0-9]* passed, 0 failed' "$TMPD/host.txt" && ok "host: all bundles incl. jarvismini carry exact bakes" || bad "host: bake checks"
python3 -I tools/symbakes/wire.py . | tee "$TMPD/wire.txt"
grep -q '^WIRE: 0 red' "$TMPD/wire.txt" && ok "wiring: taskmgr, taskbar, icon_at, jarvismini" || bad "wiring audit"
mkdir -p "$TMPD/old/kernel/user" "$TMPD/old/tools/usbimg"
for f in kernel/user/taskmgr.fi kernel/user/taskbar.fi kernel/user/fuiscene.fi tools/usbimg/build.sh; do sed 's/symvar\.\(register\|pick\)/symvar_removed/g; s/jarvismini\.symbol/jarvismini.removed/g' "$f" > "$TMPD/old/$f"; done
[ "$(python3 -I tools/symbakes/wire.py "$TMPD/old" | grep -c '^  FAIL')" -ge 5 ] && ok "counter-proof: wiring audit turns red without the calls" || bad "counter-proof: wiring audit stayed green"
cp -a assets/apps "$TMPD/oldapps"; rm -f "$TMPD"/oldapps/*/symbol44.osym "$TMPD"/oldapps/*/symbol64.osym
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps kill top"
boot() { # name scale appsdir
    local res=1280x800; [ "$2" = 2 ] && res=1920x1080
    DESIGNBUILD="$TMPD/b-$1" APPS_DIR="$3" bash tools/design/eh6.sh "$TMPD/$1" res=$res accel=kvm uiscale=$2 mode=light lang=en tafel=nein progs="$PROGS" \
        drehbuch=tools/symbakes/dreh.txt > "$TMPD/$1.log" 2>&1 < /dev/null
    rm -rf "$TMPD/b-$1"
}
for sc in 1 2; do
    boot new$sc $sc assets/apps; boot old$sc $sc "$TMPD/oldapps"
    for v in new old; do
        [ -s "$TMPD/$v$sc/tm.ppm" ] || { bad "$v scale $sc: no picture"; continue; }
        grep -a '^panic' "$TMPD/$v$sc/serial.txt" | head -2
        r=$(python3 -I tools/symbakes/tmrows.py "$TMPD/$v$sc" $sc . | tee -a "$TMPD/tm.txt"); echo "== task manager $v scale $sc"; echo "$r"
        eval "m_$v=$(sed -n 's/^MEAN //p' <<<"$r")"
    done
    python3 -I -c "import sys; sys.exit(0 if float('${m_new:-99}') <= 1.0 else 1)" && ok "task manager scale $sc: program row icon matches the SVG (mean error ${m_new:-?} <= 1.0)" || bad "task manager scale $sc: error ${m_new:-?} > 1.0"
    python3 -I -c "import sys; sys.exit(0 if float('${m_old:-0}') >= 1.5 * float('${m_new:-99}') else 1)" && ok "task manager scale $sc counter-proof: without the bakes ${m_old:-?} >= 1.5 x ${m_new:-?}" || bad "task manager scale $sc counter-proof not worse (${m_old:-?} vs ${m_new:-?})"
done
git checkout -- docs 2>/dev/null
echo "SYMBAKES: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
