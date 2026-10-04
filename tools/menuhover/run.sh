#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/menuhover/run.sh -- THE START MENU UNDER THE MOUSE (Dell bug, 04.10.2026).
#
#   bash tools/menuhover/run.sh
#
# Justin on the Dell (real hardware, Mitsubishi E55LCD, mouse): the Super key
# opens the start menu, but moving the mouse over it smeared the entry
# (and the strip around it) -- the window's own text, blurred. Cause: the
# blur of a menu window (L_MENUE, acrylic) was computed over the WHOLE window
# from what stood in the second buffer, while the window itself was painted
# only inside the dirty strip of the pointer; see `compose_one` in
# kernel/ui/wm.fi. The VM never showed it because no test moved a pointer
# over the menu with the blur on.
#
# What this run does (REAL input events through the QEMU monitor, like
# a PS/2 mouse; 1920x1080, blur on by the default theme):
#   1. boots, presses Super (the hotkey path of the Dell, not a click on
#      "Start"), takes picture 01 with the pointer far away;
#   2. moves the pointer onto each of the five entries, picture h<N> each;
#   3. clicks the entry "File Explorer" and waits for `explorer: ready`
#      (a click on a row really starts the program);
#   4. check.py: outside the pointer sprite NOTHING in the menu changed, and
#      the row under the pointer is at least 90 % as sharp as without hover;
#   5. COUNTER-PROOF: the same with the kernel flag `noglasgrow` (the rule that
#      grows the dirty area to the blurring window is off): the same checks
#      MUST find the smear, otherwise they never measured anything.
#   6. all of it twice: with the theme's default (opaque menu) and with a
#      translucent menu (`window_alpha=55`: the acrylic shows through, so a
#      blur read from the window's OWN old pixels is visible as a ghost).
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
export DESIGNBUILD="$TMPD/build"

cat > "$TMPD/dreh.txt" <<'DREH'
warteauf 'launcher: ready' || 90
warte 2
fahre 1500,300
taste meta_l
warte 2
foto 01-menu
fahreauf lzeile0
foto h0-editor
fahreauf lzeile1
foto h1-explorer
fahreauf lzeile2
foto h2-search
fahreauf lzeile3
foto h3-settings
fahreauf lzeile4
foto h4-terminal
fahreauf lzeile1
klickauf lzeile1
warteauf 'explorer: ready' || 60
warte 2
foto 20-explorer
DREH
# (the pointer waits at 1500,300: far from the menu)

run() { # run <name> <extra capture args...>
    local name=$1; shift
    bash tools/design/capture.sh "$TMPD/$name" res=1920x1080 uitrace=yes accel=kvm \
        drehbuch="$TMPD/dreh.txt" "$@" > "$TMPD/$name.log" 2>&1
    grep -a "FEHLGESCHLAGEN" "$TMPD/$name.log" | head -3
}

for V in opaque translucent; do
    ARGS=()
    [ "$V" = translucent ] && ARGS=(window_alpha=55)
    echo "== $V menu: build and run (blur on, Super key, hover, click) =="
    run "$V" "${ARGS[@]}"
    D="$TMPD/$V"
    [ -s "$D/h4-terminal.ppm" ] && ok "$V: the run took all pictures" \
        || bad "$V: pictures are missing: $(tail -3 "$TMPD/$V.log" | tr '\n' ' ')"
    grep -aq '^taskbar: startmenue auf' "$D/serial.txt" \
        && ok "$V: the Super key opened the start menu (taskbar: startmenue auf)" \
        || bad "$V: no 'startmenue auf' -- the Super key did nothing"
    grep -aq '^wm: schlieren .*blur=8' "$D/serial.txt" \
        && ok "$V: the blur is on in this run (blur=8): the check measures what the Dell has" \
        || bad "$V: the blur is not on -- the run proves nothing"
    python3 tools/menuhover/check.py "$D" sharp | sed 's/^/        /'
    python3 tools/menuhover/check.py "$D" sharp > /dev/null \
        && ok "$V: no point of the menu changed outside the pointer, every row >= 90 % as sharp" \
        || bad "$V: the menu is smeared under the pointer"
    grep -aq '^launcher: start /apps/explorer.osp/start' "$D/serial.txt" \
        && ok "$V: the click on the row File Explorer started /apps/explorer.osp/start" \
        || bad "$V: the click on the row started nothing"
    grep -aq '^explorer: ready' "$D/serial.txt" \
        && ok "$V: the file manager is up (explorer: ready)" \
        || bad "$V: no 'explorer: ready' after the click"

    echo "== $V menu, COUNTER-PROOF: without the growing rule the smear is there =="
    run "$V-ctl" extra=noglasgrow "${ARGS[@]}"
    python3 tools/menuhover/check.py "$TMPD/$V-ctl" smeared | sed 's/^/        /'
    python3 tools/menuhover/check.py "$TMPD/$V-ctl" smeared > /dev/null \
        && ok "$V: with noglasgrow the same checks find the smear (they measure something)" \
        || bad "$V: even with noglasgrow nothing was found -- the check is blind"
done

echo
echo "MENUHOVER: $pass passed, $fail failed"
[ "$fail" = 0 ]
