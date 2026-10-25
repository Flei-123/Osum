#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/startheads/run.sh -- r831: the start menu (/bin/launcher) opens on the output it is asked for (WS_STARTHEAD, `launcher --head N`;
# the taskbar of an output sets the same value before it toggles the menu).
#
#   /root/jarvis/bin/heavy bash tools/startheads/run.sh
#
# QEMU with two 640x480 outputs (vgpuheads vgpuextend): `launcher --head 1` must report a geometry inside head 1 (x >= 640, right edge <= 1280,
# bottom above the bar), `launcher --head 0` inside head 0; the control with ONE output keeps the old place (whole screen).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
. tools/lib/qemu.sh >/dev/null 2>&1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaE -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$T/bin" "$T/barbin"
PROGS="sh ls cat echo sleep orientbus act axd"
if bash tools/sync/build.sh "$T/bin" 0 $PROGS >"$T/b.txt" 2>&1 \
   && bash tools/sync/build.sh "$T/barbin" 0 taskbar launcher >"$T/b2.txt" 2>&1 \
   && ./tools/build-kernel.sh "$T/k0.img" --stufe 0 >"$T/k.txt" 2>&1; then
    ok "programs, taskbar and kernel build"
else
    bad "build failed"; tail -8 "$T/b.txt" "$T/b2.txt" "$T/k.txt" | sed 's/^/        /'
    echo "startheads: $pass ok, $fail fail"; exit 1
fi

mkg() { # mkg <head>
cat > "$T/g.sh" <<EOS
orientbus serve 0 &
sleep -m 300
axd serve 0 &
sleep 1
taskbar &
sleep 8
launcher --head $1 &
sleep 70
echo ==B-END==
act stop
echo ==FERTIG==
EOS
}
cat > "$T/taskbar.conf" <<'CONF'
edge=bottom
height=40
width=104
autohide=0
ontop=1
align=center
labels=never
pins=explorer,calc
CONF
printf 'on\n' > "$T/uitrace"
A=(build "$T/disk.img" 32768 --v3 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf"
   "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /var/ /var/log/
   /etc/ /etc/actions.d/ /etc/orientbus/
   "/etc/actions.d/a11y.actions=etc/actions.d/a11y.actions"
   "/etc/orientbus/policy=etc/orientbus/policy"
   "/etc/taskbar.conf=$T/taskbar.conf" "/etc/uitrace=$T/uitrace"
   "/bin/taskbar=$T/barbin/taskbar.elf" "/bin/launcher=$T/barbin/launcher.elf")
[ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
printf '# /etc/theme.conf\nscheme=night\nmode=dark\naccent=\nshape=modern\n' > "$T/theme.conf"
A+=("/etc/theme.conf=$T/theme.conf" /etc/schemas/)
for s in assets/schemes/*.scheme; do A+=("/etc/schemas/$(basename "$s" .scheme)=$s"); done
for p in $PROGS; do A+=("/bin/$p=$T/bin/$p.elf"); done
mkimg() { mkg "$1"; python3 tools/osum/mkfs.py "${A[@]}" "/t/g.sh=$T/g.sh" >"$T/mkfs.txt" 2>&1 || { bad "mkfs"; tail -3 "$T/mkfs.txt"; exit 1; }; }

run_case() { # run_case <tag> <max_outputs> <words> <head>
    local tag=$1 mo=$2 words=$3
    mkimg "$4"
    local sock="$T/$tag.sock"
    cp -f "$T/disk.img" "$T/$tag.img"
    ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
    timeout 330 qemu-system-x86_64 "${ACC[@]}" -kernel "$T/k0.img" -m 768 \
        -append "gfx disp wm wmdauer wmshell osum vfs bus $words script=sh /t/g.sh;exit" \
        -serial "file:$T/$tag.txt" -display none -no-reboot \
        -vga std -device virtio-gpu-pci,id=vg,max_outputs=$mo,xres=640,yres=480 -global VGA.edid=off \
        -monitor "unix:$sock,server,nowait" \
        -drive "file=$T/$tag.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$T/$tag.q" 2>&1 &
    local qp=$! i=0
    while [ $i -lt 900 ]; do
        grep -qaF "==B-END==" "$T/$tag.txt" 2>/dev/null && break
        kill -0 "$qp" 2>/dev/null || break
        sleep 0.3; i=$((i+1))
    done
    printf 'quit\n' | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1
    wait "$qp" 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$T/$tag.txt" > "$T/$tag.klar"
}

echo "== two outputs: menu on output 1, then on output 0"
run_case h1 2 "fbres=1280x480 vgpuheads vgpuextend" 1
G="$T/h1.klar"
grep -a "^launcher: geom \|^launcher: head \|^taskbar: geom " "$G" | sort -u | head -8 | sed 's/^/   /'
geom() { grep -aoE '^launcher: geom x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+' "$1" | tail -1 | sed 's/launcher: geom //'; }
chk() { # chk <file> <xmin> <xmax> <label>
    local by; by=$(grep -aoE '^taskbar: geom edge=0 x=0 y=[0-9]+' "$1" | tail -1 | sed 's/.* y=//'); by=${by:-440}
    local g x y w h; g=$(geom "$1")
    if [ -z "$g" ]; then bad "$4 -- no 'launcher: geom' line"; grep -a "^launcher\|^taskbar: head\|EXCEPTION\|ABSTURZ" "$1" | head -6 | sed 's/^/        /'; tail -n 3 "$1" | sed 's/^/        | /'; return; fi
    eval "$g"; x=$x; y=$y; w=$w; h=$h
    if [ "$x" -ge "$2" ] && [ $((x + w)) -le "$3" ] && [ $((y + h)) -le "$by" ]; then ok "$4 (x=$x y=$y w=$w h=$h)"; else bad "$4 (x=$x y=$y w=$w h=$h, wanted x in [$2,$3), bottom <= $by)"; fi
}
chk "$G" 640 1280 "launcher --head 1 stands inside output 1 above its bar"
run_case h0 2 "fbres=1280x480 vgpuheads vgpuextend" 0
chk "$T/h0.klar" 0 640 "launcher --head 0 stands inside output 0 above its bar"

echo "== r871: output 1 is a tenth shorter (vgpushort): the menu is sized for it"
run_case sh1 2 "fbres=1280x480 vgpuheads vgpuextend vgpushort" 1
grep -a "^launcher: geom " "$T/sh1.klar" | sort -u | head -4 | sed 's/^/   /'
chk "$T/sh1.klar" 640 1280 "short output 1: the menu stands inside it"
SG=$(geom "$T/sh1.klar"); eval "$SG"; SH_Y=$y; SH_H=$h
[ "$SH_H" -lt 416 ] && [ $((SH_Y + SH_H)) -le 432 ] && ok "short output 1 (432 high): menu is smaller than on a 480 output (h=$SH_H < 416) and inside it" || bad "short output 1: h=$SH_H y=$SH_Y not resized"

echo "== control: one output"
run_case one 1 "" 0
G="$T/one.klar"
chk "$G" 0 100000 "one output: the menu stands on the screen above the bar"
echo "startheads: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
