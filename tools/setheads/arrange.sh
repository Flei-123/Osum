# SPDX-License-Identifier: GPL-2.0-only
# Sourced by tools/setheads/run.sh: hotplug re-read, arrangement canvas drag, scale choice.

arrange_klar() { tr -cd '\11\12\15\40-\176' < "$T/$1.txt" > "$T/$1.klar"; }

drag_hook() {
    local tag=$1 sock=$2 i=0
    while [ $i -lt 120 ]; do
        arrange_klar "$tag"
        grep -qa "^settings: arrange cv=" "$T/$tag.klar" && break
        sleep 0.5; i=$((i+1))
    done
    python3 -I tools/setheads/drag.py "$T/$tag.klar" "$DRAG_MODE" > "$T/$tag.cmds" 2>"$T/$tag.pyerr" || cat "$T/$tag.pyerr"
    while read -r c; do
        case "$c" in
            warte*) sleep 0.4 ;;
            "") ;;
            *) printf '%s\n' "$c" | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1 ;;
        esac
    done < "$T/$tag.cmds"
    i=0
    while [ $i -lt 60 ]; do
        arrange_klar "$tag"
        grep -qaE "^settings: arrange (drop|scale)" "$T/$tag.klar" && break
        sleep 0.5; i=$((i+1))
    done
    sleep 4
    arrange_klar "$tag"
}

if [ "${SETHEADS_ONLY:-}" != drag ]; then
    echo "== hotplug re-read"
    RC_SCRIPT=g2.sh RC_WAITN=${HOT_WAITN:-3} run_case hot 2 "fbres=1280x480 vgpuheads vgpuextend"
    G="$T/hot.klar"
    grep -a "^settings: heads " "$G" | sed 's/^/   /'
    has "$G" "^settings: heads Detected: 1: 640x480  2: 640x480 *$" "hotplug: both outputs first"
    has "$G" "^settings: heads Detected: 1: 640x480 *$" "hotplug: output removed -> list shrinks"
    [ "$(grep -ac '^settings: heads Detected: 1: 640x480  2: 640x480' "$G")" -ge 2 ] && ok "hotplug: output back -> list grows again" || bad "hotplug: second two-output line missing"

    [ "${SETHEADS_ONLY:-}" = hot ] && { echo "setheads: $pass ok, $fail fail"; [ -n "$OUT" ] && cp -f "$T"/hot.klar "$OUT"/ 2>/dev/null; [ "$fail" -eq 0 ]; exit; }
    echo "== control: no hotplug"
    RC_SCRIPT=g3.sh run_case nohot 2 "fbres=1280x480 vgpuheads vgpuextend"
    G="$T/nohot.klar"
    [ "$(grep -ac '^settings: heads ' "$G")" -eq 1 ] && ok "control: heads line printed once without hotplug" || bad "control: heads line count changed without hotplug"
fi

echo "== canvas drag: valid drop below"
DRAG_MODE=below RC_SCRIPT=g3.sh RC_HOOK=drag_hook run_case dragok 2 "fbres=1280x960 vgpuheads vgpuextend"
G="$T/dragok.klar"
grep -a "^settings: arrange " "$G" | sed 's/^/   /' | head -6
has "$G" "^settings: arrange drop hd=1 to 0,480 ok *$" "drag: head 2 snapped below head 1 and accepted"
has "$G" "^settings: arrange cv=.* h1=[0-9]+,[0-9]+,[0-9]+,[0-9]+,0,480 *$" "drag: layout re-read shows position 0,480"
has "$T/dragok.conf" "^head1=0,480,100 *$" "drag: arrangement saved to /etc/displays.conf"

echo "== canvas drag: overlap rejected"
DRAG_MODE=overlap RC_SCRIPT=g3.sh RC_HOOK=drag_hook run_case dragov 2 "fbres=1280x960 vgpuheads vgpuextend"
G="$T/dragov.klar"
grep -a "^settings: arrange drop" "$G" | sed 's/^/   /'
has "$G" "^settings: arrange drop hd=1 to [0-9]+,[0-9]+ denied *$" "drag: overlapping drop denied"
grep -qa "^settings: arrange cv=.* h1=[0-9]+,[0-9]+,[0-9]+,[0-9]+,0,480" "$G" && bad "drag: denied drop moved the head" || ok "drag: denied drop left the arrangement unchanged"

echo "== canvas drag: detached rejected"
DRAG_MODE=detached RC_SCRIPT=g3.sh RC_HOOK=drag_hook run_case dragde 2 "fbres=1280x960 vgpuheads vgpuextend"
G="$T/dragde.klar"
grep -a "^settings: arrange drop" "$G" | sed 's/^/   /'
has "$G" "^settings: arrange drop hd=1 to [0-9]+,[0-9]+ denied *$" "drag: detached drop denied"

echo "== scale choice"
DRAG_MODE=scale RC_SCRIPT=g3.sh RC_HOOK=drag_hook run_case scale 2 "fbres=1280x960 vgpuheads vgpuextend"
G="$T/scale.klar"
grep -a "^settings: arrange scale" "$G" | sed 's/^/   /'
has "$G" "^settings: arrange scale hd=0 pct=150 ok *$" "scale: selected head set to 150 percent"
has "$G" "^settings: heads Detected: 1: .* 150%" "scale: monitors list shows the percent"
has "$T/scale.conf" "^head0=[0-9]+,[0-9]+,150 *$" "scale: percent saved to /etc/displays.conf"

echo "== saved arrangement restored at login"
RC_SCRIPT=g4.sh RC_WAITN=1 RC_WAIT="^settings: arrange cv=" run_case restore 2 "fbres=1280x960 vgpuheads vgpuextend"
G="$T/restore.klar"
grep -a "^settings: arrange cv=" "$G" | head -2 | sed 's/^/   /'
has "$G" "^settings: arrange cv=.* h1=[0-9]+,[0-9]+,[0-9]+,[0-9]+,0,480 *$" "restore: taskbar applied head 2 at 0,480 from /etc/displays.conf"
has "$G" "^settings: heads Detected: .*125%" "restore: saved scale 125 percent applied"
