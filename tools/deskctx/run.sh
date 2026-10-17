#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/deskctx/run.sh -- right click on the bare desktop opens a context menu (kernel/user/desktop.fi).
#
#   [BASE=<rev>] bash tools/deskctx/run.sh
#
# Four rows (catalogue key `desktop.context`): display settings, change background, settings, refresh.
# Measured on the machine of the stick (tools/design/eh6.sh, uitrace is always on there):
#   1. rklick on the empty desktop: `desktop: context open`, the picture differs from the one before inside the menu rectangle
#   2. click on row 3 (refresh): `desktop: context pick=3`, the menu is gone again (rectangle as before)
#   3. rklick again, click on row 0 (display settings): `desktop: context pick=0`, /bin/settings starts (`settings: geom`)
#   4. rklick again, Escape: the menu closes without a `pick=` line
# COUNTER-PROOF: the tree one commit before (BASE=<rev>, default HEAD~1) has no menu: no `context open`, and the picture after the
# right click equals the one before.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
BT=$TMPD/base
cleanup() { git worktree remove --force "$BT" >/dev/null 2>&1; rm -rf "$TMPD"; }
trap cleanup EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify"

cat > "$TMPD/dreh.txt" <<'EOF'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 6
foto 00-before
rklick 500,250
warte 3
foto 01-menu
klickauf dmenue3
warte 3
foto 02-after-refresh
rklick 500,250
warte 3
klickauf dmenue0
warte 8
foto 03-settings
rklick 700,400
warte 3
foto 04-menu2
taste esc
warte 3
foto 05-esc
EOF

run_tree() { # <tree> <out>
    ( cd "$1" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
      DESIGNBUILD="$2/build" bash tools/design/eh6.sh "$2/o" res=1280x800 accel=kvm progs="$PROGS" \
        drehbuch="$TMPD/dreh.txt" > "$2/o.log" 2>&1 )
}
diffpix() { # <a.ppm> <b.ppm> <x> <y> <w> <h>
    python3 -I - "$@" <<'PY'
import sys
def load(p):
    d = open(p, "rb").read(); f = []; at = 2
    while len(f) < 3:
        while d[at:at+1].isspace(): at += 1
        s = at
        while not d[at:at+1].isspace(): at += 1
        f.append(int(d[s:at]))
    return f[0], d[at+1:]
W, a = load(sys.argv[1]); _, b = load(sys.argv[2])
x0, y0, w, h = (int(v) for v in sys.argv[3:7])
n = 0
for y in range(y0, y0 + h):
    o = (y * W + x0) * 3
    if a[o:o + w * 3] != b[o:o + w * 3]:
        for x in range(w):
            if a[o + x*3:o + x*3 + 3] != b[o + x*3:o + x*3 + 3]:
                n += 1
print(n)
PY
}

mkdir -p "$TMPD/new" "$TMPD/old"
git worktree add --detach "$BT" "${BASE:-HEAD~1}" >/dev/null 2>&1 || { echo "base worktree failed"; exit 1; }
# the old tree needs the drive.py of this tree (the `dmenue` name) -- the picture and the trace lines are what differ
cp -f tools/design/drive.py "$BT/tools/design/drive.py"
run_tree "$ROOT" "$TMPD/new" &
run_tree "$BT" "$TMPD/old" &
wait
S="$TMPD/new/o/serial.txt"; SO="$TMPD/old/o/serial.txt"
if [ ! -s "$TMPD/new/o/05-esc.ppm" ]; then
    bad "no pictures: $(tail -n 3 "$TMPD/new/o.log" | tr '\n' ' ')"
    echo "DESKCTX: $pass passed, $fail failed"; exit 1
fi
if [ -n "${DESKCTX_OUT:-}" ]; then
    mkdir -p "$DESKCTX_OUT"; cp "$TMPD"/new/o/*.ppm "$DESKCTX_OUT/" 2>/dev/null; cp "$S" "$DESKCTX_OUT/serial.txt" 2>/dev/null
    cp "$TMPD"/old/o/01-menu.ppm "$DESKCTX_OUT/old-01-menu.ppm" 2>/dev/null
fi

# the menu window: the last `wlib: win id= x= y= w= h=` line before the first `context open`
ml=$(awk '/wlib: win id=[0-9]+ x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+/ {l=$0} /desktop: context open/ {print l; exit}' "$S" | grep -a -o 'x=[0-9]* y=[0-9]* w=[0-9]* h=[0-9]*')
if [ -z "$ml" ]; then
    bad "no 'desktop: context open' (or no menu window line before it)"
    mx=500; my=250; mw=120; mh=100
else
    mx=$(echo "$ml" | sed -E 's/.*x=([0-9]+).*/\1/'); my=$(echo "$ml" | sed -E 's/.*y=([0-9]+).*/\1/')
    mw=$(echo "$ml" | sed -E 's/.*w=([0-9]+).*/\1/'); mh=$(echo "$ml" | sed -E 's/.*h=([0-9]+).*/\1/')
    ok "the menu stood at $mx,$my ${mw}x$mh"
fi
d=$(diffpix "$TMPD/new/o/00-before.ppm" "$TMPD/new/o/01-menu.ppm" "$mx" "$my" "$mw" "$mh")
[ "$d" -gt $((mw * mh / 3)) ] && ok "the picture differs from the one before in $d of $((mw * mh)) pixels of the menu rectangle" \
    || bad "only $d of $((mw * mh)) pixels differ -- no menu in the picture"
grep -aq 'desktop: context pick=3' "$S" && ok "row 3 (refresh) was picked" || bad "no 'desktop: context pick=3'"
d=$(diffpix "$TMPD/new/o/00-before.ppm" "$TMPD/new/o/02-after-refresh.ppm" "$mx" "$my" "$mw" "$mh")
[ "$d" -le 60 ] && ok "after the pick the menu rectangle is as before ($d pixels differ)" || bad "the menu is still there: $d pixels differ"
grep -aq 'desktop: context pick=0' "$S" && ok "row 0 (display settings) was picked" || bad "no 'desktop: context pick=0'"
grep -aq 'settings: geom' "$S" && ok "/bin/settings started" || bad "no 'settings: geom' -- settings did not start"
n=$(grep -ac 'desktop: context pick=' "$S")
[ "$n" = 2 ] && ok "Escape closed the second menu without a pick (2 picks in total)" || bad "expected 2 picks, found $n"
d=$(diffpix "$TMPD/new/o/04-menu2.ppm" "$TMPD/new/o/05-esc.ppm" 700 400 "$mw" "$mh")
[ "$d" -gt $((mw * mh / 3)) ] && ok "the second menu is gone after Escape ($d pixels changed)" || bad "the menu survived Escape ($d pixels changed)"
# COUNTER-PROOF: the old tree has no menu
if [ ! -s "$TMPD/old/o/01-menu.ppm" ]; then
    bad "COUNTER-PROOF: no picture of the old tree"
else
    grep -aq 'desktop: context open' "$SO" && bad "COUNTER-PROOF: the old tree has a menu" || ok "COUNTER-PROOF old tree: no 'context open'"
    d=$(diffpix "$TMPD/old/o/00-before.ppm" "$TMPD/old/o/01-menu.ppm" "$mx" "$my" "$mw" "$mh")
    [ "$d" -le 60 ] && ok "COUNTER-PROOF old tree: the picture does not change ($d pixels differ)" \
        || bad "COUNTER-PROOF: the old tree changed $d pixels at the right click"
fi
echo; echo "DESKCTX: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
