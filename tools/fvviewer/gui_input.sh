#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fvviewer/gui_input.sh -- GUI gate "input": live quality of the FreeViewer window app in QEMU, against the
# Rust test host (never a real FLEI-ONE / Windows host).
#
#   /root/jarvis/bin/heavy bash tools/fvviewer/gui_input.sh [plain|tls]       (default: plain)
#
# One QEMU run; the Rust test host log (input.log) gets "### <name>" marker lines from the drehbuch, so
# tools/fvviewer/gui_input.py can judge every step on its own:
#   1. mouse     click left / right / middle, double click, drag, toolbar wheel buttons, hardware wheel (info)
#   2. scaling   the same clicks at 10 % / 90 % of the picture before and after the window was resized
#   3. keyboard  letters, shift, AltGr (@ { [ ] } \ | euro), umlauts, Ctrl+C/V/A, Alt+Tab, named keys, key repeat
#   4. clipboard guest -> host and host -> guest: ASCII, unicode, text over the size limit (cut at a character)
#   5. reconnect host killed -> 1, 2 s ... back live; 6 tries (1 2 4 8 16 30 s) -> give up + "Wiederholen";
#                "Abbrechen" during the countdown; wrong password after "Trennen" never reconnects
# Env: GUI_BUILD=<dir> keeps the build cache, GUI_RES (default 1280x800), GUI_KEEP=<dir> keeps the artefacts.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
MODE=${1:-plain}
D=$(mktemp -d); trap 'bash tools/fvviewer/th.sh "$D/th" down 2>/dev/null; pkill -P $$ 2>/dev/null; rm -rf "$D"; [ -n "${GUI_BUILD:-}" ] || rm -rf "$BUILD"' EXIT
BUILD=${GUI_BUILD:-$D/build}
mkdir -p "$BUILD" "$D/th"
RES=${GUI_RES:-1280x800}
# the guest drops keys under host load: the busier the host, the slower the typing (r80)
if [ -z "${DRIVE_TIPPE_GAP:-}" ]; then
    LOAD1=$(cut -d. -f1 /proc/loadavg)
    if [ "$LOAD1" -ge 40 ]; then DRIVE_TIPPE_GAP=0.8; elif [ "$LOAD1" -ge 20 ]; then DRIVE_TIPPE_GAP=0.5; else DRIVE_TIPPE_GAP=0.3; fi
fi
export DRIVE_TIPPE_GAP
PW=testpass123
TRY=0
MAXTRY=${GUI_INPUT_TRIES:-4}
attempt() {
BASEPORT=$(( 23000 + (($$ + 7 * TRY) % 1500) * 2 ))
RP=$BASEPORT; TP=$((BASEPORT+1))
TLS=0; [ "$MODE" = tls ] && TLS=1
rm -rf "$D/th" "$D/out" "$D/script.txt"; mkdir -p "$D/th"
ID=$(bash tools/fvviewer/th.sh "$D/th" up "$RP" "$([ "$TLS" = 1 ] && echo "$TP")") || { echo "  FAIL  test host stack did not start"; exit 1; }
echo "== gui_input ($MODE): relay $RP host id $ID =="
if [ "$TLS" = 1 ]; then
    echo "10.0.2.2 $TP tls xclip" > "$D/fvviewer.test"; cp "$D/th/ca.pem" "$D/ca.pem"
else
    echo "10.0.2.2 $RP xclip" > "$D/fvviewer.test"; : > "$D/ca.pem"
fi
TH="bash $ROOT/tools/fvviewer/th.sh $D/th"
LOG="$D/th/input.log"
M() { echo "extern echo '### $1' >> $LOG"; }   # marker in the test host log

{
cat <<EOF
warteauf 'launcher: ready' || 90
warte 4
taste meta_l
warte 2
tippe fvviewer
warte 2
taste ret
warteaufmuss 'fvviewer: rect name=go' || 60
warte 3
klickauf fvrectid
warte 2
klickauf fvrectid
warte 1
tippe $ID
warte 2
klickauf fvrectpw
warte 2
klickauf fvrectpw
warte 1
tippe $PW
warte 1
klickauf fvrectgo
warteaufmuss 'fvviewer: connect start id_len=${#ID} pw_len=${#PW}' || 20
warteauf 'fvviewer: state live' || 120
# clipboard scenarios run by themselves (unicode, then the oversize text) -> wait for their echo
warteauf 'fvviewer: clip unicode echo ok' || 60
warteauf 'fvviewer: clip big echo' || 90
warte 6
foto 20-live
EOF
M mouse-left;  echo "klickauf fvpt10x10"; echo "warte 1"
M mouse-right; echo "rklickauf fvpt90x10"; echo "warte 1"
M mouse-middle; echo "mklickauf fvpt50x90"; echo "warte 1"
M mouse-double; echo "doppelauf fvpt30x70"; echo "warte 1"
M mouse-drag; echo "ziehauf fvpt20x20 fvpt80x80"; echo "warte 2"
M wheel-up; echo "klickauf fvrectwup"; echo "warte 1"
M wheel-down; echo "klickauf fvrectwdown"; echo "warte 1"
M wheel-hw; echo "fahreauf fvpt50x50"; echo "monitor mouse_move 0 0 -1"; echo "warte 1"; echo "monitor mouse_move 0 0 1"; echo "warte 1"
M scale-before-10; echo "klickauf fvpt10x10"; echo "warte 1"
M scale-before-90; echo "klickauf fvpt90x90"; echo "warte 1"
echo "foto 25-before-resize"
M resize
# drag the lower right corner of the window (80,50 + 860x640 + frame) inwards, then out again
echo "ziehe 940,723 760,560"; echo "warte 4"; echo "foto 26-smaller"
M scale-small-10; echo "klickauf fvpt10x10"; echo "warte 1"
M scale-small-90; echo "klickauf fvpt90x90"; echo "warte 1"
echo "ziehe 760,560 1000,740"; echo "warte 4"; echo "foto 27-bigger"
M scale-big-10; echo "klickauf fvpt10x10"; echo "warte 1"
M scale-big-90; echo "klickauf fvpt90x90"; echo "warte 1"
# keyboard: focus into the picture first (a click), then one marker per key
M key-focus; echo "klickauf fvpt50x50"; echo "warte 1"
for k in a shift-a shift-1 spc ret esc tab backspace left right up down delete home end pgup pgdn f1 f5 \
         alt_r-q alt_r-7 alt_r-8 alt_r-9 alt_r-0 alt_r-minus alt_r-less alt_r-e \
         bracket_left semicolon apostrophe minus shift-bracket_left \
         ctrl-c ctrl-v ctrl-a; do
    M "key-$k"; echo "taste $k"; echo "warte 0.6"
done
# Alt+Tab as a KEY is taken by the guest window manager (it switches windows, the viewer loses focus and all later
# input goes elsewhere); the viewer's own Alt+Tab is the toolbar button below. Click into the picture to be sure.
M key-refocus; echo "klickauf fvpt50x50"; echo "warte 1"
M key-repeat; echo "taste z 1500"; echo "warte 2"
M key-done
echo "foto 30-keys"
# toolbar: Strg+Alt+Entf, Win, Alt+Tab buttons
M bar-cad; echo "klickauf fvrectcad"; echo "warte 1"
M bar-alttab; echo "klickauf fvrectalttab"; echo "warte 1"
M bar-win; echo "klickauf fvrectwin"; echo "warte 1"
# ---- reconnect R1: host away for a moment -> 1 s, 2 s tries, then live again
cat <<EOF
marke 'fvviewer: state live'
extern $TH host-kill
warteauf 'fvviewer: reconnect attempt=2 wait_s=2' || 90
foto 35-reconnecting
extern $TH host-start
warteneu 'fvviewer: state live' || 120
warte 4
foto 36-reconnected
# ---- R2: host away for good -> six tries (1 2 4 8 16 30 s), then the form with "Wiederholen"
marke 'fvviewer: give up'
extern $TH host-kill
warteauf 'fvviewer: give up kind=4 tries=6 retry_button=1' || 200
warte 3
foto 37-gave-up
extern $TH host-start
warte 3
klickauf fvrectretry
warteauf 'fvviewer: state live' || 120
warte 4
# ---- R3: "Abbrechen" in the countdown, then "Wiederholen"
marke 'fvviewer: reconnect cancelled'
extern $TH host-kill
# the 16 s wait of try 5 leaves time for the (slow, loaded) click; the 8 s wait of try 4 was too short
warteauf 'fvviewer: reconnect attempt=5 wait_s=16' || 150
klickauf fvrectcancel
warteauf 'fvviewer: reconnect cancelled' || 20
foto 38-cancelled
extern $TH host-start
warte 5
klickauf fvrectretry
warteneu 'fvviewer: state live' || 120
warte 4
# ---- R4: wrong password after "Trennen": error at once, no automatic try, no "Wiederholen" for a refusal
klickauf fvrectbye
warte 3
klickauf fvrectpw
warte 2
tippe x
warte 1
foto 39-wrong-pw-form
klickauf fvrectgo
warteauf 'fvviewer: give up kind=6' || 90
warte 12
foto 40-wrong-pw
EOF
} > "$D/script.txt"

# the extern lines of M() contain the literal marker text; make sure the file is ASCII
DESIGNBUILD="$BUILD" EH_APPEND=rtcutc EH_APP_PROGS=fvviewer \
    EH_MKFS_EXTRA="/etc/fvviewer.test=$D/fvviewer.test@0644 /etc/fvviewer-ca.pem=$D/ca.pem@0644 /apps/ /apps/fvviewer.osp/ /apps/fvviewer.osp/INFO=pakete/fvviewer/INFO@0644 /apps/fvviewer.osp/start@/bin/fvviewer" \
    timeout 1700 bash tools/design/eh6.sh "$D/out" "res=$RES" accel=kvm netz=ja moreprogs=fvviewer tafel=nein "drehbuch=$D/script.txt" > "$D/eh6.log" 2>&1
}
while :; do
    attempt
    # guard: the viewer logs the field lengths when "Verbinden" is pressed. A lost key press while typing the
    # ID or the password (OrientOS drops keys under load) makes the length differ -> wrong run, type again.
    first=$(grep -a -m1 'fvviewer: connect start' "$D/out/serial.txt" 2>/dev/null)
    case "$first" in
        *"id_len=${#ID} pw_len=${#PW}"*) break ;;
    esac
    TRY=$((TRY+1))
    echo "  INFO  typing check failed ('${first:-no connect line}', wanted id_len=${#ID} pw_len=${#PW}) -> try $TRY/$MAXTRY"
    bash tools/fvviewer/th.sh "$D/th" down 2>/dev/null
    [ "$TRY" -ge "$MAXTRY" ] && { echo "  FAIL  typing check: id/password never typed completely in $MAXTRY runs"; break; }
done
grep -a 'FEHLGESCHLAGEN\|NICHT DA\|Traceback\|KEIN RECHTECK' "$D/eh6.log" | head -12
if [ -n "${GUI_KEEP:-}" ]; then mkdir -p "$GUI_KEEP"; cp "$D"/out/*.ppm "$D"/out/serial.txt "$D"/th/input.log "$D"/th/host.log "$D"/script.txt "$D"/eh6.log "$GUI_KEEP/" 2>/dev/null; fi
python3 -I tools/fvviewer/gui_input.py "$D/out/serial.txt" "$D/th/input.log"
rc=$?
echo "GUI INPUT GATE ($MODE): rc=$rc"
exit $rc
