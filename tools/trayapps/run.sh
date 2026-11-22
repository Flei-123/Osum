#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/trayapps/run.sh -- background apps in the tray: bar field, overflow tiles, pin/unpin, drag, menus, persistence.
#
#   bash tools/trayapps/run.sh                 TRAYAPPS_OUT=<dir> keeps pictures + serial logs
#   TRAYAPPS_OLD=0 skips the old-tree counter-proof
#
# /run/tray.items is seeded with three owners (alpha pinned to the bar by tray_apps, beta + gamma in the overflow).
# Boot A (scale 1): click on the bar icon runs the open command, overflow tile menu -> "Show on taskbar" pins beta,
#   right click on the bar icon opens the menu, a custom entry runs, drag bar -> overflow and back.
# Boot S (scale 2): bar icons inked and centred.  Boot B (restart): the saved places are the preset.
# Boot C (counter-proof): no registry, no bar icons.  Boot O (counter-proof): old origin/main tree, no bar icons.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"; git worktree remove --force "$OLD" 2>/dev/null' EXIT
OLD="$TMPD/old"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify"
PIX=tools/trayapps/pixels.py
PIN_BUTTON=${TRAYAPPS_PIN_BUTTON:-4}
MARK_BUTTON=1

printf 'alpha|57514|Alpha ready|notify ran-alpha-open|||Mark|notify ran-alpha-mark||\nbeta|57505|Beta ready|notify ran-beta-open|||Mark|notify ran-beta-mark||\ngamma|57586|Gamma ready|notify ran-gamma-open|||Mark|notify ran-gamma-mark||\n' > "$TMPD/tray.items"

cat > "$TMPD/dreh_a.txt" <<SCRIPT
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 8
foto 00-bar
klickauf trayapp0
warteauf 'traypop: click id=' || 20
warte 3
foto 01-click
klickauf chevron
warteauf 'traypop: open' || 25
warte 3
foto 02-overflow
rklickauf traytile0
warteauf 'traypop: menu id=' || 15
warte 3
foto 03-menu
klickauf traymenu$PIN_BUTTON
warteauf 'traypop: places' || 15
warte 5
foto 04-pinned
marke 'traypop: menu id='
rklickauf trayapp1
warteneu 'traypop: menu id=' || 15
warte 3
foto 05-barmenu
klickauf traymenu$MARK_BUTTON
warteauf 'traypop: pick id=' || 15
warte 4
klickauf chevron
warteauf 'traypop: open' || 25
warte 3
ziehvon trayapp1 traytile0
warteauf 'traydrag: end' || 25
warte 5
foto 06-dragged
SCRIPT
cat > "$TMPD/dreh_s.txt" <<'SCRIPT'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 8
foto 00-bar
SCRIPT
cat > "$TMPD/dreh_b.txt" <<'SCRIPT'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 8
foto 00-bar
klickauf chevron
warteauf 'traypop: open' || 25
warte 3
foto 01-popup
SCRIPT

boot() { # name script uiscale tbextra seed [tree]
    local O="$TMPD/o-$1" tree="${6:-.}" extra=""
    [ "$5" = yes ] && extra="/run/ /run/tray.items=$TMPD/tray.items@0644"
    (cd "$tree" && DESIGNBUILD="$TMPD/build-$1" EH_MKFS_EXTRA="$extra" bash tools/design/eh6.sh "$O" res=1280x800 accel=kvm mode=light \
        uiscale="$3" progs="$PROGS" tbextra="$4" drehbuch="$2" > "$TMPD/o-$1.log" 2>&1 < /dev/null)
    if [ -n "${TRAYAPPS_OUT:-}" ]; then mkdir -p "$TRAYAPPS_OUT/$1"; cp "$O"/*.ppm "$O/serial.txt" "$TMPD/o-$1.log" "$TRAYAPPS_OUT/$1/" 2>/dev/null; fi
}

BASE="tray_chevron=1;tray_apps=alpha:1"
boot a "$TMPD/dreh_a.txt" 1 "$BASE" yes &
boot s "$TMPD/dreh_s.txt" 2 "$BASE" yes &
boot c "$TMPD/dreh_s.txt" 1 "$BASE" no &
if [ "${TRAYAPPS_OLD:-1}" = 1 ]; then
    git worktree add --detach "$OLD" origin/main > /dev/null 2>&1 && cp tools/design/drive.py "$OLD/tools/design/drive.py" \
        && boot o "$TMPD/dreh_s.txt" 1 "$BASE" yes "$OLD" &
fi
wait
SA="$TMPD/o-a/serial.txt"
if [ ! -s "$SA" ]; then bad "A: no serial log: $(tail -n 3 "$TMPD/o-a.log" | tr '\n' ' ')"; echo "TRAYAPPS: $pass passed, $fail failed"; exit 1; fi

has() { grep -aq -- "$2" "$1"; }
has "$SA" 'taskbar: app icon 0 ' && ok "A: the bar reports app icon 0" || bad "A: no 'taskbar: app icon 0'"
has "$SA" 'traypop: item .*owner=beta' && has "$SA" 'traypop: item .*owner=gamma' && ok "A: beta + gamma are overflow tiles" || bad "A: overflow items missing"
has "$SA" 'traypop: item .*owner=alpha' && bad "A: alpha (pinned) is also in the overflow" || ok "A: alpha is not in the overflow"
has "$SA" 'traypop: click id=[0-9]* owner=alpha' && ok "A: click on the bar icon reports the owner" || bad "A: no click line for alpha"
has "$SA" 'toast .ran-alpha-open' && ok "A: the open command of alpha ran" || bad "A: no toast from the open command"
n0=$(grep -a -m1 'traypop: open n=' "$SA" | sed -E 's/.* n=([0-9]+).*/\1/')
[ "$n0" -ge 2 ] 2>/dev/null && ok "A: overflow tile count $n0" || bad "A: overflow tile count '$n0'"
has "$SA" 'traypop: menu id=' && ok "A: right click on a tile opens the item menu" || bad "A: no item menu"
has "$SA" 'traypop: places .*beta:1' && ok "A: pin through the menu saved beta:1" || bad "A: places line lacks beta:1"
has "$SA" 'taskbar: app icon 1 ' && ok "A: after the pin the bar shows a second app icon" || bad "A: no second app icon"
[ "$(grep -ac 'traypop: menu id=' "$SA")" -ge 2 ] && ok "A: right click on a bar icon opens the menu" || bad "A: no menu from the bar icon"
has "$SA" 'toast .ran-beta-mark' && ok "A: the custom menu command of beta ran" || bad "A: no toast from the custom command"
has "$SA" 'traypop: pick id=' && ok "A: menu pick reported" || bad "A: no pick line"
has "$SA" 'traydrag: move slot=[0-9]* to=1' && ok "A: drag bar -> overflow moved the app" || bad "A: no 'traydrag: move ... to=1'"
has "$SA" 'traypop: places .*beta:2' && ok "A: the drag saved beta:2" || bad "A: places line lacks beta:2 after the drag"
for f in 00-bar 01-click 02-overflow 03-menu 04-pinned 05-barmenu 06-dragged; do [ -s "$TMPD/o-a/$f.ppm" ] || bad "A: picture $f missing"; done

pixel_checks() { # name dir tolerance
    local S="$2/serial.txt" r x y w h tol=$3
    r=$(python3 -I $PIX rect "$S" 0)
    if [ "$r" = none ]; then bad "$1: no app rect"; return; fi
    read -r x y w h <<< "$r"
    read -r colours inked cx2 cy2 <<< "$(python3 -I $PIX ink "$2/00-bar.ppm" "$x" "$y" "$w" "$h")"
    [ "$colours" -ge 4 ] && [ "$inked" -ge 20 ] && ok "$1: the app icon is inked ($colours colours, $inked px)" || bad "$1: flat app cell ($colours colours, $inked px)"
    [ "${cx2#-}" -le $((2 * tol)) ] && [ "${cy2#-}" -le $((2 * tol)) ] && ok "$1: the glyph is centred in its cell (off by $cx2/$cy2 half px)" || bad "$1: the glyph is off centre ($cx2/$cy2 half px)"
}
pixel_checks "A scale 1" "$TMPD/o-a" 2
[ -s "$TMPD/o-s/serial.txt" ] && pixel_checks "S scale 2" "$TMPD/o-s" 3 || bad "S: no serial log"
d=$(python3 -I $PIX diff "$TMPD/o-a/00-bar.ppm" "$TMPD/o-a/04-pinned.ppm" 0 740 1280 60)
[ "$d" -gt 100 ] && ok "A: the bar picture changed after the pin ($d px)" || bad "A: the bar picture did not change ($d px)"
d2=$(python3 -I $PIX diff "$TMPD/o-a/02-overflow.ppm" "$TMPD/o-a/03-menu.ppm" 600 300 680 440)
[ "$d2" -gt 500 ] && ok "A: the item menu is in the picture ($d2 px)" || bad "A: the menu changed only $d2 px"

restart_check() { # name places expected-bar-icons
    boot "$1" "$TMPD/dreh_b.txt" 1 "tray_chevron=1;tray_apps=$2" yes
    local S="$TMPD/o-$1/serial.txt" pb nb
    pb=$(grep -a -m1 'traypop: open n=' "$S" | sed -E 's/.* n=([0-9]+).*/\1/')
    nb=$(grep -a 'taskbar: app icon ' "$S" | sed -E 's/.*app icon ([0-9]+) .*/\1/' | sort -u | wc -l)
    [ "$nb" = "$3" ] && ok "$1: after the restart the bar holds $nb app icon(s) (places $2)" || bad "$1: $nb bar app icon(s), expected $3 (places $2)"
    [ "$pb" -ge 1 ] 2>/dev/null && ok "$1: the popup holds $pb tile(s) after the restart" || bad "$1: popup tiles '$pb'"
}
pinned=$(grep -a 'traypop: places ' "$SA" | head -1 | sed 's/.*traypop: places //')
final=$(grep -a 'traypop: places ' "$SA" | tail -1 | sed 's/.*traypop: places //')
if [ -n "$pinned" ] && [ -n "$final" ]; then
    restart_check b1 "$pinned" 2
    restart_check b2 "$final" 1
else
    bad "B: no saved places line"
fi
conf=$(python3 -I tools/osum/mkfs.py cat "$TMPD/o-a/disk.img" /etc/taskbar.conf 2>/dev/null | grep -a '^tray_apps=')
[ -n "$conf" ] && ok "A: /etc/taskbar.conf on the disk holds '$conf'" || bad "A: no tray_apps line in /etc/taskbar.conf on the disk"

SC="$TMPD/o-c/serial.txt"
if [ -s "$SC" ]; then
    has "$SC" 'taskbar: app icon ' && bad "C: bar icons without a registry" || ok "C: counter-proof: no registry, no bar app icons"
else bad "C: no serial log"; fi
SO="$TMPD/o-o/serial.txt"
if [ "${TRAYAPPS_OLD:-1}" = 1 ]; then
    if [ -s "$SO" ]; then
        has "$SO" 'taskbar: app icon ' && bad "O: the old tree shows app icons" || ok "O: counter-proof: the old tree has no bar app icons"
    else bad "O: no serial log for the old tree"; fi
fi
echo; echo "TRAYAPPS: $pass passed, $fail failed"
[ "$fail" = 0 ]
