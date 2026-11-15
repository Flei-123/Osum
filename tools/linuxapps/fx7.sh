#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${1:?workdir}
OUT=${2:?outdir}
mkdir -p "$OUT"
SOCK="$OUT/mon.sock"
wait_marker() {
    local pattern=$1 waited=0
    until grep -qa "$pattern" "$OUT/ser.txt" 2>/dev/null || [ "$waited" -ge "${FX7_MARKERCAP:-420}" ]; do sleep 5; waited=$((waited + 5)); done
    sleep "${FX7_PAINTWAIT:-60}"
}
url_painted() { python3 -I tools/linuxapps/f7pix.py "$OUT/url.ppm" 00c800 > /dev/null; }
poll_url_paint() {
    local n=0
    while [ "$n" -lt "${FX7_URLPOLLS:-10}" ]; do
        mon "screendump $OUT/url.ppm"; sleep 3
        url_painted && return 0
        echo "url poll $n red" >> "$OUT/poll.log"
        sleep "${FX7_URLPOLLGAP:-12}"; n=$((n + 1))
    done
    return 1
}
wait_nav_paint() {
    local n=0
    until grep -qa "nav=[1-9]" "$OUT/ser.txt" 2>/dev/null || [ "$n" -ge "${FX7_MARKERCAP:-420}" ]; do sleep 5; n=$((n + 5)); done
    n=0
    while [ "$n" -lt "${FX7_NAVPOLLS:-20}" ]; do
        mon "screendump $OUT/nav.ppm"; sleep 3
        python3 -I tools/linuxapps/f7pix.py "$OUT/nav.ppm" 0000c8 > /dev/null && break
        sleep "${FX7_NAVPOLLGAP:-5}"; n=$((n + 1))
    done
    sleep "${FX7_SETTLE:-10}"
}
build_guest_script() {
    local name
    for name in $(compgen -v FX7_); do printf '%s=%q\n' "$name" "${!name}"; done > "$OUT/fx7-guest.sh"
    cat tools/linuxapps/guest-fx7-input.sh >> "$OUT/fx7-guest.sh"
}
click_page_until() {
    local pattern=$1 try=0 waited
    while [ "$try" -lt "${FX7_CLICKTRIES:-4}" ]; do
        mon "mouse_move 2 2"; sleep 1; mon "mouse_move -2 -2"; sleep 1
        mon "mouse_button 1"; sleep 1; mon "mouse_button 0"
        waited=0
        until grep -qa "$pattern" "$OUT/ser.txt" 2>/dev/null || [ "$waited" -ge "${FX7_CLICKWAIT:-60}" ]; do sleep 5; waited=$((waited + 5)); done
        grep -qa "$pattern" "$OUT/ser.txt" 2>/dev/null && return 0
        try=$((try + 1))
    done
    return 1
}
drag_select() {
    mon "mouse_move ${FX7_DRAGX0:--650} ${FX7_DRAGY0:--164}"; sleep 2
    mon "mouse_button 1"; sleep 1
    mon "mouse_move ${FX7_DRAGDX:-245} 0"; sleep 2
    mon "mouse_button 0"; sleep 5
}
double_click_word() {
    mon "mouse_move ${FX7_DBLDX:--210} 0"; sleep 2
    mon "mouse_button 1"; mon "mouse_button 0"; mon "mouse_button 1"; mon "mouse_button 0"; sleep 5
}
select_popup() {
    local dy=${FX7_POPDY:-110} key
    mon "mouse_button 1"; sleep 1; mon "mouse_button 0"; sleep ${FX7_POPWAIT:-8}
    mon "screendump $OUT/popup.ppm"; sleep 3
    for key in down down ret; do mon "sendkey $key"; sleep 2; done
    sleep 3
    mon "mouse_button 1"; sleep 1; mon "mouse_button 0"; sleep ${FX7_POPWAIT:-8}
    mon "mouse_move 0 $dy"; sleep 2
    mon "mouse_button 1"; sleep 1; mon "mouse_button 0"; sleep 5
    mon "mouse_move 0 -$dy"; sleep 3
}
resize_window() {
    mon "sendkey meta_l-up"; sleep ${FX7_RESIZEWAIT:-15}
    mon "screendump $OUT/resize.ppm"; sleep 3
}
mon() { printf '%s\n' "$1" | socat - "UNIX-CONNECT:$SOCK" > /dev/null 2>&1; }
(
    i=0
    until grep -qa 'wayd: window c=' "$OUT/ser.txt" 2>/dev/null; do sleep 2; i=$((i + 2)); [ "$i" -gt 1500 ] && exit 0; done
    j=0
    until grep -qa 'FXLOAD' "$OUT/ser.txt" 2>/dev/null || [ "$j" -ge "${FX7_LOADWAIT:-150}" ]; do sleep 2; j=$((j + 2)); done
    sleep 15
    if [ -n "${FX7_NOINPUT:-}" ]; then
        sleep 60
        mon "screendump $OUT/nav.ppm"; sleep 3
        mon "screendump $OUT/url.ppm"; sleep 3
        exit 0
    fi
    for k in a b c shift-d backspace left x; do mon "sendkey $k"; sleep 2; done
    sleep 5
    for k in pgdn pgdn pgdn end; do mon "sendkey $k"; sleep 3; done
    mon "mouse_move 60 40"; sleep 1; click_page_until "nav=[1-9]"; wait_nav_paint
    mon "screendump $OUT/nav.ppm"; sleep 3
    mon "mouse_button 2"; sleep 1; mon "mouse_button 0"; sleep 3
    if [ "${FX7_POPUP:-1}" != 0 ]; then select_popup; fi
    if [ "${FX7_POINTER:-1}" != 0 ]; then
        drag_select
        double_click_word
        resize_window
    fi
    for n in 1 2 3 4 5 6; do mon "mouse_move 0 0 -1"; sleep ${FX7_WHEELGAP:-3}; done
    sleep 20; mon "sendkey ctrl-l"; sleep ${FX7_URLFOCUSWAIT:-30}
    for k in f i l e shift-semicolon slash slash slash t m p slash i n dot h t m l shift-slash u; do mon "sendkey $k"; sleep 2; done
    mon "sendkey ret"; wait_marker "url=[1-9]"
    poll_url_paint
    mon "sendkey f9"
) &
DP=$!
trap 'kill $DP 2>/dev/null' EXIT
build_guest_script
GUI=1 DONE=FX-END BLOCKS=${BLOCKS:-1000000} TMO=${TMO:-1500} MEM=${MEM:-3072} \
    EXTRA="/etc/fx3.sh=$OUT/fx7-guest.sh@755" \
    KARGS="gfx disp wm wmdauer wmshell osum vfs bus fremdtrace nic nip=10.0.2.15/24 ngw=10.0.2.2 script=sh /etc/fx.sh;exit" \
    QEMU_EXTRA="-netdev user,id=n0 -device e1000,netdev=n0" \
    bash tools/linuxapps/run.sh "$WD" tools/linuxapps/guest-fx3-boot.sh "$OUT"
