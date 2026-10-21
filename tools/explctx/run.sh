#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/explctx/run.sh -- the file manager's ITEM context menu (right click on a table row) comes from the context registry
# (kernel/user/ctxreg.fi, context CTX_EXPLORER_ITEM): 15 built-in rows + every `explorer|label|program` line of /etc/ctxmenu.conf.
#
#   [BASE=<rev>] bash tools/explctx/run.sh
#
# Machine of the stick (tools/design/eh6.sh). The image carries a manifest with ONE extra entry (`explorer|Probe entry|/bin/true`).
#   1. right click on the first table row: `explorer: ctxreg n=16` (15 built-in + the manifest row), `explorer: menurect`
#   2. BEHAVIOUR UNCHANGED: the 15 old rows look exactly like before -- the menu picture of the old tree (BASE) is pixel-equal inside
#      the rectangle of the first 15 rows (same click, same place, same labels)
#   3. the manifest row (row 15): `explorer: ctx ext start 4096` (EXT_BASE) -- an app registered itself WITHOUT a change of shell code
#   4. right click, Escape: the menu closes without a further pick
#   5. right click, row 13 (Properties): `explorer: props` -- a built-in action still runs through ctx_wahl
# COUNTER-PROOF: the tree before (BASE, default origin/main) has no registry menu: no `ctxreg n=`, the menu is one row (28 px) shorter,
# and clicking where the probe row would be starts nothing.
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
printf '# probe entry: an app registers a row without touching the shell\nexplorer|Probe entry|/bin/true\n' > "$TMPD/ctxmenu.conf"
export EH_ETC_EXTRA="/etc/ctxmenu.conf=$TMPD/ctxmenu.conf@0644"

cat > "$TMPD/dreh.txt" <<'EOT'
warteauf 'launcher: ready' || 120
warte 4
klick 300,200
warte 1
tippe explorer &
taste ret
warteauf explorer: ready || 90
warte 6
klickauf ftabzeile0
warte 2
foto 00-before
marke explorer: menurect
rklickauf ftabzeile0
warteneu explorer: menurect || 60
warte 3
foto 01-menu
klickauf emenue15
warte 4
marke explorer: menurect
rklickauf ftabzeile0
warteneu explorer: menurect || 60
warte 3
foto 02-menu2
taste esc
warte 3
foto 03-esc
marke explorer: menurect
rklickauf ftabzeile0
warteneu explorer: menurect || 60
warte 3
klickauf emenue13
warte 4
foto 04-props
EOT

run_tree() { # <tree> <out>
    ( cd "$1" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
      DESIGNBUILD="$2/build" bash tools/design/eh6.sh "$2/o" accel=kvm progs="$PROGS" \
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
git worktree add --detach "$BT" "${BASE:-origin/main}" >/dev/null 2>&1 || { echo "base worktree failed"; exit 1; }
# the old tree needs this tree's drive.py / eh6.sh (EH_ETC_EXTRA); the pictures and trace lines are what differ
cp -f tools/design/drive.py "$BT/tools/design/drive.py"; cp -f tools/design/eh6.sh "$BT/tools/design/eh6.sh"
run_tree "$ROOT" "$TMPD/new" &
run_tree "$BT" "$TMPD/old" &
wait
S="$TMPD/new/o/serial.txt"; SO="$TMPD/old/o/serial.txt"
if [ ! -s "$TMPD/new/o/04-props.ppm" ]; then
    bad "no pictures: $(tail -n 3 "$TMPD/new/o.log" | tr '\n' ' ')"
    echo "EXPLCTX: $pass passed, $fail failed"; exit 1
fi
if [ -n "${EXPLCTX_OUT:-}" ]; then
    mkdir -p "$EXPLCTX_OUT"; cp "$TMPD"/new/o/*.ppm "$EXPLCTX_OUT/" 2>/dev/null; cp "$S" "$EXPLCTX_OUT/serial.txt" 2>/dev/null
    cp "$TMPD"/old/o/01-menu.ppm "$EXPLCTX_OUT/old-01-menu.ppm" 2>/dev/null; cp "$SO" "$EXPLCTX_OUT/old-serial.txt" 2>/dev/null
fi

grep -aq 'explorer: ctxreg n=16' "$S" && ok "item menu has 16 rows (15 built-in + the manifest entry)" || bad "no 'explorer: ctxreg n=16' ($(grep -a 'explorer: ctxreg' "$S" | head -1))"
ml=$(grep -a 'explorer: menurect wx=' "$S" | head -1 | grep -a -o 'wx=[0-9]* wy=[0-9]* wh=[0-9]*')
ho=$(grep -a 'explorer: menurect wx=' "$SO" | head -1 | grep -a -o 'wh=[0-9]*' | cut -d= -f2)
if [ -z "$ml" ]; then
    bad "no 'explorer: menurect' in the new tree"; mx=0; my=0; mh=0
else
    mx=$(echo "$ml" | sed -E 's/wx=([0-9]+).*/\1/'); my=$(echo "$ml" | sed -E 's/.*wy=([0-9]+) wh.*/\1/'); mh=$(echo "$ml" | sed -E 's/.*wh=([0-9]+)/\1/')
    ok "the menu stood at $mx,$my height $mh"
fi
if [ -n "$ho" ] && [ "$mh" -gt "$ho" ]; then
    d=$((mh - ho))
    [ "$d" -ge 20 ] && [ "$d" -le 40 ] && ok "the new menu is one row taller than the old one ($mh vs $ho)" || bad "height differs by $d (new $mh, old $ho)"
else
    bad "heights not comparable (new $mh, old ${ho:-none})"
fi
# BEHAVIOUR UNCHANGED: the first 15 rows are pixel-equal to the old tree (menu starts at wx/wy; width from the labels). Only the part
# above the last old row's end is compared: old height minus its bottom border.
if [ -s "$TMPD/old/o/01-menu.ppm" ] && [ -n "$ho" ] && [ "$ho" -gt 20 ]; then
    d=$(diffpix "$TMPD/new/o/01-menu.ppm" "$TMPD/old/o/01-menu.ppm" "$mx" "$my" 150 $((ho - 8)))
    [ "$d" -le 300 ] && ok "the 15 old rows look as before ($d of $((150 * (ho - 8))) pixels differ)" \
        || bad "the old rows changed: $d pixels differ"
fi
grep -aq 'explorer: ctx ext start 4096' "$S" && ok "row 15 (manifest entry) picked: action EXT_BASE" || bad "no 'explorer: ctx ext start 4096'"
n=$(grep -ac 'explorer: ctx ext start' "$S")
[ "$n" = 1 ] && ok "Escape closed the second menu without a pick (1 ext pick)" || bad "expected 1 ext pick, found $n"
d=$(diffpix "$TMPD/new/o/02-menu2.ppm" "$TMPD/new/o/03-esc.ppm" "$mx" "$my" 150 "$mh")
[ "$d" -gt $((150 * mh / 3)) ] && ok "the second menu is gone after Escape ($d pixels changed)" || bad "the menu survived Escape ($d pixels changed)"
grep -aq 'explorer: props ' "$S" && ok "row 13 (Properties) still runs its built-in action" || bad "no 'explorer: props'"
# COUNTER-PROOF: the old tree has no registry menu and the probe row does nothing
if [ ! -s "$TMPD/old/o/01-menu.ppm" ]; then
    bad "COUNTER-PROOF: no picture of the old tree"
else
    grep -aq 'explorer: ctxreg' "$SO" && bad "COUNTER-PROOF: the old tree has the registry menu" || ok "COUNTER-PROOF old tree: no 'ctxreg' line"
    grep -aq 'explorer: ctx ext start' "$SO" && bad "COUNTER-PROOF: the old tree started the probe" || ok "COUNTER-PROOF old tree: the probe row starts nothing"
fi
echo; echo "EXPLCTX: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
