#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/traypop/run.sh -- THE TRAY FLYOUT (kernel/user/traypop.fi), light and dark. (W-TRAY6)
#
#   bash tools/traypop/run.sh            # both modes
#   TRAYPOP_MODES=dark bash tools/traypop/run.sh
#   TRAYPOP_OUT=<dir> keeps pictures + serial log
#
# The bar runs with `tray_chevron=1`; /etc/tray.items registers two overflow items and the stub mic line.
# Per mode (machine of the stick, tools/design/eh6.sh, 1280x800):
#   1. click on the chevron -> serial `traypop: open n=<items> x= y= w= h=`
#   2. the picture differs from the one before inside exactly that rectangle and holds ink (glyphs + text)
#   3. both item lines are reported (`traypop: item`), the bar did not say `no traypop`
#   4. a second click on the chevron -> `traypop: shut`, the rectangle is as before again (COUNTER-PROOF)
#   5. COUNTER-PROOF: the first picture (flyout closed) has no `traypop: open` before the click
#   6. (W-MERGEB2) tile RASTER (tools/traypop/raster.py): one tile size, even pitch, inside the flyout; icon centre within 1 px of
#      the tile centre; hover on tile 0 changes tile 0 and not tile 1; right click on tile 0 -> `traypop: menu id=` (item 0) + a
#      menu in the picture; Esc leaves the menu (back to the list), a second Esc shuts (`traypop: shut esc`, rectangle as before).
#      Counter-proofs inside raster.py (a moved tile / a shifted icon is caught).
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
MODES=${TRAYPOP_MODES:-"light dark"}
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify"

printf 'backup|7|Backup is running\nchat|8|Chat: 2 unread\nmic|1|0\n' > "$TMPD/tray.items"
cat > "$TMPD/dreh.txt" <<'EOF'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 6
foto 00-before
klickauf chevron
warteauf 'traypop: open' || 25
warte 3
foto 01-open
fahreauf traytile0
warte 2
foto 03-hover
rklickauf traytile0
warteauf 'traypop: menu' || 15
warte 2
foto 04-menu
taste esc
warte 2
foto 05-back
taste esc
warteauf 'traypop: shut esc' || 15
warte 3
foto 06-esc
klickauf chevron
warte 4
klickauf chevron
warteauf 'traypop: shut toggle' || 25
warte 3
foto 02-shut
EOF

diffpix() { # <a.ppm> <b.ppm> <x> <y> <w> <h> -> number of different pixels
    python3 - "$@" <<'PY'
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
distinct() { # <ppm> <x> <y> <w> <h> -> number of distinct colours (text + glyphs make many)
    python3 - "$@" <<'PY'
import sys
d = open(sys.argv[1], "rb").read(); f = []; at = 2
while len(f) < 3:
    while d[at:at+1].isspace(): at += 1
    s = at
    while not d[at:at+1].isspace(): at += 1
    f.append(int(d[s:at]))
at += 1
W = f[0]
x0, y0, w, h = (int(v) for v in sys.argv[2:6])
c = set()
for y in range(y0, y0 + h, 1):
    o = at + (y * W + x0) * 3
    for x in range(0, w, 1):
        c.add(d[o+x*3:o+x*3+3])
print(len(c))
PY
}

for MODE in $MODES; do
    echo "== $MODE"
    O="$TMPD/o-$MODE"
    EH_MKFS_EXTRA="/etc/tray.items=$TMPD/tray.items@0644" bash tools/design/eh6.sh "$O" res=1280x800 accel=kvm mode="$MODE" progs="$PROGS" \
        tbextra="tray_chevron=1" drehbuch="$TMPD/dreh.txt" > "$TMPD/o-$MODE.log" 2>&1 < /dev/null
    S="$O/serial.txt"
    if [ -n "${TRAYPOP_OUT:-}" ]; then mkdir -p "$TRAYPOP_OUT/$MODE"; cp "$O"/*.ppm "$S" "$TRAYPOP_OUT/$MODE/" 2>/dev/null; fi
    if [ ! -s "$O/02-shut.ppm" ] || [ ! -s "$O/06-esc.ppm" ]; then
        bad "$MODE: no pictures: $(tail -n 3 "$TMPD/o-$MODE.log" | tr '\n' ' ')"
        continue
    fi
    grep -aq 'taskbar: chevron x=' "$S" && ok "$MODE: the bar reports a chevron" || bad "$MODE: no 'taskbar: chevron' line"
    ol=$(grep -a 'traypop: open n=' "$S" | head -1 | sed 's/.*traypop: open/traypop: open/')
    if [ -z "$ol" ]; then bad "$MODE: no 'traypop: open' after the click"; continue; fi
    n=$(echo "$ol" | sed -E 's/.* n=([0-9]+).*/\1/'); x=$(echo "$ol" | sed -E 's/.* x=([0-9]+).*/\1/'); y=$(echo "$ol" | sed -E 's/.* y=([0-9]+).*/\1/')
    w=$(echo "$ol" | sed -E 's/.* w=([0-9]+).*/\1/'); h=$(echo "$ol" | sed -E 's/.* h=([0-9]+).*/\1/')
    ok "$MODE: serial '$ol'"
    [ "$n" -ge 2 ] && ok "$MODE: both registered items are in the flyout (n=$n)" || bad "$MODE: n=$n, expected >= 2 overflow items"
    d=$(diffpix "$O/00-before.ppm" "$O/01-open.ppm" "$x" "$y" "$w" "$h")
    [ "$d" -gt $((w * h / 3)) ] && ok "$MODE: the picture differs inside the rectangle ($d of $((w * h)) px)" || bad "$MODE: only $d of $((w * h)) px differ -- no flyout in the picture"
    dc=$(distinct "$O/01-open.ppm" "$x" "$y" "$w" "$h")
    [ "$dc" -ge 12 ] && ok "$MODE: glyphs + text inked ($dc colours)" || bad "$MODE: flat rectangle ($dc colours)"
    ic=$(grep -ac 'traypop: item ' "$S")
    [ "$ic" -ge 2 ] && ok "$MODE: $ic 'traypop: item' lines" || bad "$MODE: $ic 'traypop: item' lines"
    grep -aq 'traypop: item .*owner=backup' "$S" && grep -aq 'traypop: item .*owner=chat' "$S" && ok "$MODE: owners backup + chat reported" || bad "$MODE: owner lines missing"
    grep -aq 'traypop: shut' "$S" && ok "$MODE: second click on the chevron shuts it" || bad "$MODE: no 'traypop: shut'"
    d2=$(diffpix "$O/00-before.ppm" "$O/02-shut.ppm" "$x" "$y" "$w" "$h")
    [ "$d2" -le 3000 ] && ok "$MODE: after the shut the rectangle is as before ($d2 px differ; the clock ticks)" || bad "$MODE: the flyout is still in the picture ($d2 px differ)"
    # W-MERGEB2: the raster, hover, right click, Esc
    while IFS= read -r l; do case "$l" in "OK "*) ok "${l#OK    }" ;; "FAIL "*) bad "${l#FAIL  }" ;; esac; done \
        < <(python3 -I tools/traypop/raster.py "$S" "$O/01-open.ppm" "$O/03-hover.ppm" "$O/04-menu.ppm" "$MODE")
    d3=$(diffpix "$O/04-menu.ppm" "$O/05-back.ppm" "$x" "$y" "$w" "$h")
    [ "$d3" -ge 2000 ] && ok "$MODE: the first Esc leaves the item menu (the list is back, $d3 px differ)" || bad "$MODE: the first Esc changed only $d3 px"
    grep -aq 'traypop: shut esc' "$S" && ok "$MODE: the second Esc shuts the flyout (traypop: shut esc)" || bad "$MODE: no 'traypop: shut esc'"
    d4=$(diffpix "$O/00-before.ppm" "$O/06-esc.ppm" "$x" "$y" "$w" "$h")
    [ "$d4" -le 3000 ] && ok "$MODE: after the Esc the rectangle is as before ($d4 px differ)" || bad "$MODE: the flyout stayed in the picture after Esc ($d4 px)"
    grep -aq 'taskbar: no traypop' "$S" && bad "$MODE: the bar has no traypop host" || ok "$MODE: the bar had a host"
done
echo; echo "TRAYPOP: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
