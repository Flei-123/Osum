#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/pkgshadow/run.sh -- r2338: store packages must not bring old pixel icons or a second "Editor" back.
# Boots the desktop with a stale package bundle edit.osp (pixel icon, name=Editor) next to editor.osp and searches "e":
# the start menu rows must match the SVG symbols of explorer, editor, settings and show exactly one Editor row.
# Counter-proof: the same boot without editor.osp shows the stale pixel row and must be clearly worse.
#   /root/jarvis/bin/heavy bash tools/pkgshadow/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit nedit sh echo ls cat theme"
stale() {
    local d=$1
    mkdir -p "$d/edit.osp/data"
    printf 'name=Editor\ninfo=Write and change text\nkeys=editor,text,edit,note\nfassung=1\n' > "$d/edit.osp/INFO"
    printf '/bin/edit\n' > "$d/edit.osp/start.txt"
    printf 'stale package bundle\n' > "$d/edit.osp/data/README"
    cp assets/apps/editor.osp/symbol.txt "$d/edit.osp/symbol.txt"
}
cp -a assets/apps "$TMPD/with"; stale "$TMPD/with"
cp -a assets/apps "$TMPD/without"; stale "$TMPD/without"; rm -rf "$TMPD/without/editor.osp"
boot() {
    DESIGNBUILD="$TMPD/b-$1" APPS_DIR="$TMPD/$2" bash tools/design/eh6.sh "$TMPD/$1" res=1280x800 accel=kvm uiscale=1 mode=light lang=en tafel=nein progs="$PROGS" \
        drehbuch=tools/rowicons/script.txt > "$TMPD/$1.log" 2>&1 < /dev/null
    rm -rf "$TMPD/b-$1"
}
boot new with; boot old without
for v in new old; do
    [ -s "$TMPD/$v/01-search.ppm" ] || { bad "$v: no picture"; continue; }
    python3 -I tools/pkgshadow/rows.py "$TMPD/$v" . > "$TMPD/$v.txt"; cat "$TMPD/$v.txt"
done
rows_of() { sed -n 's/^ROWS //p' "$TMPD/$1.txt"; }
mean_of() { sed -n 's/^MEAN //p' "$TMPD/$1.txt"; }
[ "$(rows_of new)" = "1" ] && ok "one Editor row with the stale package present" || bad "Editor rows with stale package: '$(rows_of new)'"
python3 -I -c "import sys; sys.exit(0 if float('$(mean_of new)') <= 1.0 else 1)" && ok "rows match the SVG symbols (mean error $(mean_of new) <= 1.0)" || bad "row icon error $(mean_of new) > 1.0"
python3 -I -c "import sys; sys.exit(0 if float('$(mean_of old)') >= 2.0 * float('$(mean_of new)') else 1)" && ok "counter-proof: stale package alone is worse ($(mean_of old) >= 2 x $(mean_of new))" || bad "counter-proof not worse ($(mean_of old) vs $(mean_of new))"
echo "PKGSHADOW: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
