#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/barctx/run.sh -- right click on the EMPTY task bar opens a context menu (kernel/user/taskbar_ctx.fi, rows from the registry
# kernel/user/ctxreg.fi): task manager, display settings, settings, plus every `taskbar|label|program` line of /etc/ctxmenu.conf.
#
#   [BASE=<rev>] bash tools/barctx/run.sh
#
# Machine of the stick (tools/design/eh6.sh, 1280x800, bar at the bottom). The image carries a manifest with ONE extra entry.
#   1. rklick on the empty bar: `taskbar: kontext leer x= y= w= h= n=4` (3 built-in rows + the manifest row), the picture differs
#      inside the menu rectangle
#   2. row 0 (task manager): `kontext leer w=10`; row 2 (settings): `kontext leer w=11` and `settings: ready`
#   3. row 3 (the manifest entry): `kontext leer w=4096` (EXT_BASE) -- an app registered itself WITHOUT a change of shell code
#   4. rklick, Escape: the menu closes without a `w=` line
# COUNTER-PROOF: the tree before the feature (BASE, default fc893814~1 = before the registry) has no menu on the empty bar: no `kontext leer`, the
# picture after the right click equals the one before.
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
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq"
BARY=${BARY:-790}
printf '# probe entry: an app registers a row without touching the shell\ntaskbar|Probe entry|/bin/true\n' > "$TMPD/ctxmenu.conf"
export EH_ETC_EXTRA="/etc/ctxmenu.conf=$TMPD/ctxmenu.conf@0644"

cat > "$TMPD/dreh.txt" <<EOT
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 6
foto 00-before
rklick 700,$BARY
warte 3
foto 01-menu
klickauf bmenue0
warte 4
rklick 700,$BARY
warte 3
klickauf bmenue2
warte 10
foto 02-settings
rklick 700,$BARY
warte 3
klickauf bmenue3
warte 4
rklick 700,$BARY
warte 3
foto 03-menu2
taste esc
warte 3
foto 04-esc
EOT

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
git worktree add --detach "$BT" "${BASE:-fc893814~1}" >/dev/null 2>&1 || { echo "base worktree failed"; exit 1; }
# the old tree needs this tree's drive.py (the `bmenue` name) and eh6.sh (EH_ETC_EXTRA); the pictures and trace lines are what differ
cp -f tools/design/drive.py "$BT/tools/design/drive.py"; cp -f tools/design/eh6.sh "$BT/tools/design/eh6.sh"
run_tree "$ROOT" "$TMPD/new" &
run_tree "$BT" "$TMPD/old" &
wait
S="$TMPD/new/o/serial.txt"; SO="$TMPD/old/o/serial.txt"
if [ ! -s "$TMPD/new/o/04-esc.ppm" ]; then
    bad "no pictures: $(tail -n 3 "$TMPD/new/o.log" | tr '\n' ' ')"
    echo "BARCTX: $pass passed, $fail failed"; exit 1
fi
if [ -n "${BARCTX_OUT:-}" ]; then
    mkdir -p "$BARCTX_OUT"; cp "$TMPD"/new/o/*.ppm "$BARCTX_OUT/" 2>/dev/null; cp "$S" "$BARCTX_OUT/serial.txt" 2>/dev/null
    cp "$TMPD"/old/o/01-menu.ppm "$BARCTX_OUT/old-01-menu.ppm" 2>/dev/null
fi

ml=$(grep -a -m1 'taskbar: kontext leer x=' "$S" | grep -a -o 'x=[0-9]* y=[0-9]* w=[0-9]* h=[0-9]* n=[0-9]*')
if [ -z "$ml" ]; then
    bad "no 'taskbar: kontext leer' with a rectangle"
    mx=600; my=700; mw=160; mh=100
else
    mx=$(echo "$ml" | sed -E 's/.*x=([0-9]+) y.*/\1/'); my=$(echo "$ml" | sed -E 's/.*y=([0-9]+) w.*/\1/')
    mw=$(echo "$ml" | sed -E 's/.* w=([0-9]+) h.*/\1/'); mh=$(echo "$ml" | sed -E 's/.* h=([0-9]+) n.*/\1/')
    nr=$(echo "$ml" | sed -E 's/.* n=([0-9]+).*/\1/')
    ok "the menu stood at $mx,$my ${mw}x$mh"
    [ "$nr" = 4 ] && ok "4 rows: 3 built-in + the manifest entry" || bad "expected 4 rows, found $nr"
fi
d=$(diffpix "$TMPD/new/o/00-before.ppm" "$TMPD/new/o/01-menu.ppm" "$mx" "$my" "$mw" "$mh")
[ "$d" -gt $((mw * mh / 3)) ] && ok "the picture differs from the one before in $d of $((mw * mh)) pixels of the menu rectangle" \
    || bad "only $d of $((mw * mh)) pixels differ -- no menu in the picture"
grep -aq 'taskbar: kontext leer w=10' "$S" && ok "row 0 (task manager) was picked" || bad "no 'kontext leer w=10'"
grep -aq 'taskbar: kontext leer w=11' "$S" && grep -aq 'settings: ready' "$S" && ok "row 2 (settings) picked, /bin/settings started" \
    || bad "settings row: no 'w=11' or no 'settings: ready'"
grep -aq 'taskbar: kontext leer w=4096' "$S" && ok "row 3 (manifest entry) picked: action EXT_BASE" || bad "no 'kontext leer w=4096'"
n=$(grep -ac 'taskbar: kontext leer w=' "$S")
[ "$n" = 3 ] && ok "Escape closed the last menu without a pick (3 picks in total)" || bad "expected 3 picks, found $n"
d=$(diffpix "$TMPD/new/o/03-menu2.ppm" "$TMPD/new/o/04-esc.ppm" "$mx" "$my" "$mw" "$mh")
[ "$d" -gt $((mw * mh / 3)) ] && ok "the second menu is gone after Escape ($d pixels changed)" || bad "the menu survived Escape ($d pixels changed)"
# COUNTER-PROOF: the tree before has no menu on the empty bar
if [ ! -s "$TMPD/old/o/01-menu.ppm" ]; then
    bad "COUNTER-PROOF: no picture of the old tree"
else
    grep -aq 'taskbar: kontext leer' "$SO" && bad "COUNTER-PROOF: the old tree has the menu" || ok "COUNTER-PROOF old tree: no 'kontext leer'"
    d=$(diffpix "$TMPD/old/o/00-before.ppm" "$TMPD/old/o/01-menu.ppm" "$mx" "$my" "$mw" "$mh")
    [ "$d" -le 300 ] && ok "COUNTER-PROOF old tree: the picture does not change ($d pixels differ)" \
        || bad "COUNTER-PROOF: the old tree changed $d pixels at the right click"
fi
echo; echo "BARCTX: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
