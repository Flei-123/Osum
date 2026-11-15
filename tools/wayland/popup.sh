#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/brand-env.sh"
# SPDX-License-Identifier: GPL-2.0-only
# tools/wayland/popup.sh -- wayd object lifetime and xdg_popup, with a real libwayland client (tools/wayland/wlpop.c).
#
#   bash tools/wayland/popup.sh [<work dir>]        (start it through /root/jarvis/bin/heavy)
#
#   1. object churn: 300 rounds of create + destroy for region, positioner, surface, xdg_surface, xdg_popup, touch, pointer,
#      keyboard, shm pool and buffer. A leaked object fills the 128 slot table and wayd kills the connection (counter-proof:
#      BASE_WAYD=<elf> runs the same client against an older wayd)
#   2. xdg_popup: positioner placement (anchor + gravity), configure, a frameless window at the parent origin + placement,
#      pixels on the screen, a click inside the popup reaches the popup surface, a click outside sends popup_done and the
#      window goes away
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

TMPD=${1:-$(mktemp -d)}
[ -n "${1:-}" ] || trap 'rm -rf "$TMPD"' EXIT
mkdir -p "$TMPD/bin"
WLB=${WLBUILD:-/root/wl-build}
PROGS="sh sleep echo cat ls wayd"
POPUP_X=40; POPUP_Y=50; POPUP_W=120; POPUP_H=80
RING_CLEAR=6; RING_SHADE=4; PARENT_GREY=242; SHADE_EXPECT=121; TOLERANCE=2

echo "== 1. build =="
. tools/lib/firnenv.sh
if python3 tools/wayland/gen.py 2>/dev/null | cmp -s - kernel/user/wlproto.fi; then
    ok "wlproto.fi is what gen.py generates"
else
    bad "kernel/user/wlproto.fi differs from tools/wayland/gen.py"
fi
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "firnc0 builds $(echo $PROGS | wc -w) programs"
else
    bad "the programs do not build"; tail -15 "$TMPD/b.txt" | sed 's/^/        /'
    echo "WL-POPUP: $pass passed, $fail failed"; exit 1
fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then
    ok "the kernel builds"
else
    bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'
    echo "WL-POPUP: $pass passed, $fail failed"; exit 1
fi
if [ -f "$WLB/musl-root/lib/libwayland-client.a" ] && musl-gcc -static -O2 -nostartfiles \
        -T tools/foreign/osum.ld -Wl,--build-id=none -D_GNU_SOURCE \
        -I"$WLB/musl-root/include" -I"$WLB/wayland-1.21.0/gen" -o "$TMPD/wlpop" \
        tools/foreign/start.s tools/foreign/osum_main.c tools/wayland/wlpop.c \
        "$WLB/wayland-1.21.0/gen/xdg-shell-protocol.c" \
        -L"$WLB/musl-root/lib" -lwayland-client -lffi 2>"$TMPD/wl.txt"; then
    ok "wlpop: a Wayland program, libwayland-client + xdg-shell, static musl"
else
    bad "wlpop does not build (needs $WLB)"
    grep -v 'GNU-stack\|deprecated' "$TMPD/wl.txt" | head -5 | sed 's/^/        /'
    echo "WL-POPUP: $pass passed, $fail failed"; exit 1
fi

cat > "$TMPD/g.sh" <<EOS
wayd /tmp/wayland-0 2000000000 ${WAYD_TRACE:-} &
sleep 2
wlpop /tmp/wayland-0 240 P churn popup ring &
sleep 5
echo ==W-READY==
sleep 700
echo ==FERTIG==
EOS
A=(build "$TMPD/disk.img" 32768 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf"
   "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /var/ /var/log/ /etc/ /usr/ /usr/share/ /usr/share/wayd/
   "/bin/wlpop=$TMPD/wlpop" "/t/g.sh=$TMPD/g.sh")
[ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
for p in $PROGS; do
    if [ "$p" = wayd ] && [ -n "${BASE_WAYD:-}" ]; then A+=("/bin/wayd=$BASE_WAYD"); else A+=("/bin/$p=$TMPD/bin/$p.elf"); fi
done
bash tools/mkfsfi/mkfs.sh "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "the disk: $(stat -c%s "$TMPD/disk.img") octets" \
    || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt" | sed 's/^/        /'; echo "WL-POPUP: $pass passed, $fail failed"; exit 1; }

echo "== 2. boot: window server, wayd, one Wayland program =="
SOCK="$TMPD/mon.sock"; rm -f "$SOCK"
ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
timeout 900 qemu-system-x86_64 "${ACC[@]}" -kernel "$TMPD/k0.img" -m 768 \
    -append "gfx disp wm wmdauer wmshell osum vfs bus script=sh /t/g.sh;exit" \
    -serial "file:$TMPD/ser.txt" -display none -no-reboot -vga std \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/qemu.txt" 2>&1 &
QPID=$!
trap 'kill $QPID 2>/dev/null; [ -n "${1:-}" ] || rm -rf "$TMPD"' EXIT
waitfor() {
    local i=0
    while [ $i -lt $(( $2 * 5 )) ]; do
        grep -qaF -- "$1" "$TMPD/ser.txt" 2>/dev/null && return 0
        kill -0 "$QPID" 2>/dev/null || return 1
        sleep 0.2; i=$((i + 1))
    done
    return 1
}
clean() { tr -cd '\11\12\15\40-\176' < "$TMPD/ser.txt" | tr -d '\r'; }
L() { clean | grep -ao "wlpop\[P\]: .*"; }
klick() {
    python3 tools/themestore/click.py "$1,$2" > "$TMPD/c.txt" 2>/dev/null
    python3 tools/wm/monitor.py "$SOCK" "$TMPD/c.txt" > /dev/null 2>&1
    sleep 2
}
shot() {
    printf 'screendump %s\n' "$1" | timeout 20 socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1
    sleep 3
}
pixels() { # ppm x y [x y ...] -> r,g,b per point
    python3 - "$@" <<'PYEOF'
import sys
f = open(sys.argv[1], 'rb').read()
parts = f.split(None, 4)
w, h = int(parts[1]), int(parts[2])
off = len(f) - w * h * 3
a = sys.argv[2:]
out = []
for i in range(0, len(a), 2):
    x, y = int(a[i]), int(a[i + 1])
    j = off + (y * w + x) * 3
    out.append("%d,%d,%d" % tuple(f[j:j + 3]))
print(" ".join(out))
PYEOF
}
has()    { grep -qaF -- "$2" <<< "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" <<< "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
num() { sed -E "s/.* $2=([0-9]+).*/\1/" <<< "$1" | head -1; }

waitfor "==W-READY==" 400 && ok "wayd and the client are up" || { bad "the script did not get ready"; clean | tail -30 | sed 's/^/        /'; }
waitfor "popup up" 120 || waitfor "churn FAIL" 5
sleep 3

echo "== 3. object churn =="
has "$(L)" "window up" "wlpop opened its toplevel"
has "$(L)" "churn ok rounds=300 err=0" "300 rounds of create + destroy: the connection survived, no protocol error"
hasnot "$(L)" "churn FAIL" "no round failed"

echo "== 4. xdg_popup =="
has "$(L)" "popup configure x=$POPUP_X y=$POPUP_Y w=$POPUP_W h=$POPUP_H" "xdg_popup.configure carries the placement from the positioner (anchor top-left + gravity bottom-right)"
GEOM=$(clean | grep -ao "wayd: window c=0 x=[0-9]* y=[0-9]* inx=[0-9]* iny=[0-9]* w=[0-9]* h=[0-9]*" | tail -1)
PGX=$(( $(num "$GEOM" x) + $(num "$GEOM" inx) )); PGY=$(( $(num "$GEOM" y) + $(num "$GEOM" iny) ))
note "parent content origin: $PGX,$PGY"
PW=$(clean | grep -ao "wayd: popup win c=0 x=[0-9]* y=[0-9]* w=[0-9]* h=[0-9]*" | tail -1)
note "$PW"
[ "$(num "$PW" x)" = "$((PGX + POPUP_X))" ] && [ "$(num "$PW" y)" = "$((PGY + POPUP_Y))" ] \
    && ok "the popup window sits at the parent origin + placement" || bad "popup window position '$PW' (want $((PGX + POPUP_X)),$((PGY + POPUP_Y)))"
[ "$(num "$PW" w)" = "$POPUP_W" ] && [ "$(num "$PW" h)" = "$POPUP_H" ] && ok "the popup window is ${POPUP_W}x${POPUP_H}" || bad "popup window size"
hasnot "$(clean | grep -ao 'wayd: no wm.*')" "no wm" "no window creation failure"
shot "$TMPD/open.ppm"
PX=$((PGX + POPUP_X)); PY=$((PGY + POPUP_Y))
px=$(pixels "$TMPD/open.ppm" $((PX + 60)) $((PY + 40)) $((PX + 2)) $((PY + 2)) $((PX - 6)) $((PY + 40)) $((PX + POPUP_W + 6)) $((PY + 40)) $((PX + 60)) $((PY + POPUP_H + 6)))
note "pixels: $px"
read -r c_in c_corner c_left c_right c_below <<< "$px"
[ "$c_in" = "224,0,0" ] && [ "$c_corner" = "224,0,0" ] && ok "the popup is on the screen (224,0,0) inside and in its corner" || bad "popup pixels inside: $c_in $c_corner"
[ "$c_left" = "242,242,242" ] && [ "$c_right" = "242,242,242" ] && [ "$c_below" = "242,242,242" ] \
    && ok "COUNTER-PROOF: the parent shows around the popup (no smear)" || bad "pixels around the popup: $c_left $c_right $c_below"

M=$(L | wc -l)
klick $((PX + 60)) $((PY + 40))
AFTER=$(L | tail -n +$((M + 1)))
has "$AFTER" "ptr enter on=popup" "a click inside the popup: wl_pointer.enter on the popup surface"
has "$AFTER" "ptr button button=272 state=1" "the button press reaches the client"
hasnot "$AFTER" "popup done" "a click inside the popup does not dismiss it"

M=$(L | wc -l)
klick $((PGX + 250)) $((PGY + 150))
AFTER=$(L | tail -n +$((M + 1)))
has "$AFTER" "popup done" "a click outside the popup sends xdg_popup.popup_done"
hasnot "$AFTER" "ptr button button=272 state=1" "the dismissing click is not delivered to the parent"
sleep 3
has "$(L)" "popup surface destroyed" "the client destroyed the popup after popup_done (no protocol error)"
shot "$TMPD/closed.ppm"
px=$(pixels "$TMPD/closed.ppm" $((PX + 60)) $((PY + 40)))
[ "$px" = "242,242,242" ] && ok "the popup window is gone from the screen" || bad "after popup_done the pixel is $px"

near() { # r,g,b expected-r,g,b
    local IFS=','; local -a a=($1) e=($2); local i
    for i in 0 1 2; do
        [ $(( ${a[$i]} - ${e[$i]} )) -le $TOLERANCE ] && [ $(( ${e[$i]} - ${a[$i]} )) -le $TOLERANCE ] || return 1
    done
}

echo "== 5. per-pixel alpha =="
waitfor "popup ring up" 60 && ok "the client opened a popup with an ARGB buffer (clear ring, half-black ring, red inside)" || bad "no ARGB popup"
sleep 4
shot "$TMPD/ring.ppm"
px=$(pixels "$TMPD/ring.ppm" $((PX + 2)) $((PY + 2)) $((PX + RING_CLEAR + 1)) $((PY + 40)) $((PX + POPUP_W - RING_CLEAR - 2)) $((PY + 40)) $((PX + 60)) $((PY + 40)))
note "pixels: $px"
read -r c_clear c_shade c_shade_far c_core <<< "$px"
near "$c_clear" "$PARENT_GREY,$PARENT_GREY,$PARENT_GREY" && ok "alpha 0 shows the parent behind the popup, not black ($c_clear)" || bad "alpha 0 pixel is $c_clear"
near "$c_shade" "$SHADE_EXPECT,$SHADE_EXPECT,$SHADE_EXPECT" && near "$c_shade_far" "$SHADE_EXPECT,$SHADE_EXPECT,$SHADE_EXPECT" \
    && ok "half-black pixels are blended with the parent ($c_shade, $c_shade_far)" || bad "shade pixels $c_shade $c_shade_far (want about $SHADE_EXPECT)"
[ "$c_core" = "224,0,0" ] && ok "opaque pixels stay as they are" || bad "opaque pixel is $c_core"

kill $QPID 2>/dev/null
wait $QPID 2>/dev/null
echo "WL-POPUP: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
