#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/traydrag/run.sh -- drag and drop of the system tray icons between the bar and the overflow popup.
#
#   bash tools/traydrag/run.sh            TRAYDRAG_OUT=<dir> keeps pictures + serial logs
#
# Boot A (tray_hidden=14: battery, sound, network start in the popup, popup tile 0 = battery):
#   1. drag popup tile 0 onto the clock: serial `traydrag: begin`, `move ... to=0`, `end ... saved=1`, hidden mask 14 -> 6
#   2. drag the battery field back onto popup tile 0: hidden mask 6 -> 14
# Boot B (restart): the order/hidden values saved by step 1 are the preset; the bar lays out the fields in the same order.
# Boot C (counter-proof): same preset, no drag: no `traydrag:` line, the order stays the default.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify"
ORDER=tools/traydrag/order.py

cat > "$TMPD/dreh_a.txt" <<'SCRIPT'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 6
foto 00-before
klickauf chevron
warteauf 'traypop: open' || 25
warte 3
foto 01-popup
ziehvon traytile0 uhr
warteauf 'traydrag: end slot=3 saved=1 order=[0-9]+ hidden=6' || 25
warte 4
foto 02-in-bar
ziehvon akku traytile0
warteauf 'traydrag: end slot=3 saved=1 order=[0-9]+ hidden=14' || 25
warte 4
foto 03-back
SCRIPT
cat > "$TMPD/dreh_c.txt" <<'SCRIPT'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 6
klickauf chevron
warteauf 'traypop: open' || 25
warte 3
fahreauf traytile0
warte 2
klickauf traytile0
warte 4
foto 00-control
SCRIPT
cat > "$TMPD/dreh_b.txt" <<'SCRIPT'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 8
foto 00-restart
SCRIPT

boot() { # name script tbextra
    local O="$TMPD/o-$1"
    DESIGNBUILD="$TMPD/build-$1" bash tools/design/eh6.sh "$O" res=1280x800 accel=kvm mode=light progs="$PROGS" \
        tbextra="$3" drehbuch="$2" > "$TMPD/o-$1.log" 2>&1 < /dev/null
    if [ -n "${TRAYDRAG_OUT:-}" ]; then mkdir -p "$TRAYDRAG_OUT/$1"; cp "$O"/*.ppm "$O/serial.txt" "$TRAYDRAG_OUT/$1/" 2>/dev/null; fi
}

BASE="tray_chevron=1;tray_hidden=14"
boot a "$TMPD/dreh_a.txt" "$BASE" &
boot c "$TMPD/dreh_c.txt" "$BASE" &
wait
SA="$TMPD/o-a/serial.txt"; SC="$TMPD/o-c/serial.txt"
if [ ! -s "$SA" ]; then bad "A: no serial log: $(tail -n 3 "$TMPD/o-a.log" | tr '\n' ' ')"; echo "TRAYDRAG: $pass passed, $fail failed"; exit 1; fi

nb=$(python3 -I $ORDER count "$SA")
[ "$nb" -ge 2 ] && ok "A: $nb drags started" || bad "A: only $nb drag(s) started"
grep -aq 'traydrag: move slot=3 to=0' "$SA" && ok "A: battery moved from the popup to the bar" || bad "A: no 'move slot=3 to=0'"
grep -aq 'traydrag: move slot=3 to=1' "$SA" && ok "A: battery moved back to the popup" || bad "A: no 'move slot=3 to=1'"
mapfile -t ENDS < <(python3 -I $ORDER ends "$SA")
set -- ${ENDS[0]:-}; first_hidden=${4:-}; first_order=${3:-}; first_saved=${2:-}
set -- ${ENDS[1]:-}; second_hidden=${4:-}; second_saved=${2:-}
[ "$first_hidden" = 6 ] && [ "$first_saved" = 1 ] && ok "A: first drop saved, hidden mask 14 -> 6, order $first_order" || bad "A: first end '${ENDS[0]:-}'"
[ "$second_hidden" = 14 ] && [ "$second_saved" = 1 ] && ok "A: second drop saved, hidden mask back to 14" || bad "A: second end '${ENDS[1]:-}'"
for f in 00-before 01-popup 02-in-bar 03-back; do [ -s "$TMPD/o-a/$f.ppm" ] || bad "A: picture $f missing"; done
cmp -s "$TMPD/o-a/01-popup.ppm" "$TMPD/o-a/02-in-bar.ppm" && bad "A: the picture did not change after the drag" || ok "A: the picture changed after the first drag"

order_a=$(python3 -I $ORDER after-first "$SA")
if [ -n "$first_order" ]; then
    boot b "$TMPD/dreh_b.txt" "tray_chevron=1;tray_order=$first_order;tray_hidden=$first_hidden"
    order_b=$(python3 -I $ORDER final "$TMPD/o-b/serial.txt")
    [ -n "$order_b" ] && [ "$order_a" = "$order_b" ] && ok "B: after the restart the bar order is the dragged one ($order_b)" || bad "B: order after restart '$order_b', after the drag '$order_a'"
else
    bad "B: no saved order to restart with"
fi

[ ! -s "$SC" ] && bad "C: no serial log" || {
    nc=$(python3 -I $ORDER count "$SC")
    [ "$nc" = 0 ] && ok "C: counter-proof: no drag without a pointer move ($nc begin lines)" || bad "C: $nc drag begin lines without a drag"
    order_c=$(python3 -I $ORDER final "$SC")
    [ -n "$order_c" ] && [ "$order_c" != "$order_a" ] && ok "C: counter-proof: the bar order differs from the dragged one ($order_c vs $order_a)" || bad "C: order '$order_c' equals the dragged order '$order_a'"
}
echo; echo "TRAYDRAG: $pass passed, $fail failed"
[ "$fail" = 0 ]
