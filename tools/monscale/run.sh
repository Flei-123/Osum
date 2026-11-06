#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
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
mkdir -p "$T/bin"
PROGS="sh ls cat echo sleep orientbus act axd taskbar scaledemo"
if bash tools/sync/build.sh "$T/bin" 0 $PROGS >"$T/b.txt" 2>&1 && ./tools/build-kernel.sh "$T/k0.img" --stufe 0 >"$T/k.txt" 2>&1; then
    ok "programs and kernel build"
else
    bad "build failed"; tail -8 "$T/b.txt" "$T/k.txt"; exit 1
fi
printf 'on\n' > "$T/uitrace"
printf 'edge=bottom\nheight=40\nwidth=104\nautohide=0\nontop=1\nalign=center\nlabels=never\npins=explorer,calc\n' > "$T/taskbar.conf"

run_case() {
    local pct=$1 xres=$2 yres=$3 win2="$4" d="$T/c$1"
    mkdir -p "$d"
    printf 'heads=extend\nhead1=0,%s,%s\n' "$yres" "$pct" > "$d/displays.conf"
    printf 'orientbus serve 0 &\nsleep -m 300\naxd serve 0 &\nsleep 1\ntaskbar &\nsleep 8\nscaledemo 100 20 1 &\nscaledemo %s 0 &\nsleep 150\necho ==B-END==\n' "$win2" > "$d/g.sh"
    local A=(build "$d/disk.img" 32768 --v3 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /var/ /var/log/
       /etc/ /etc/actions.d/ /etc/orientbus/
       "/etc/actions.d/a11y.actions=etc/actions.d/a11y.actions" "/etc/orientbus/policy=etc/orientbus/policy"
       "/etc/uitrace=$T/uitrace" "/etc/taskbar.conf=$T/taskbar.conf" "/etc/displays.conf=$d/displays.conf" /etc/schemas/
       /usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/en/ "/usr/share/locale/en/messages=locale/en/messages")
    [ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
    local s p
    for s in assets/schemes/*.scheme; do A+=("/etc/schemas/$(basename "$s" .scheme)=$s"); done
    for p in $PROGS; do A+=("/bin/$p=$T/bin/$p.elf"); done
    bash tools/mkfsfi/mkfs.sh "${A[@]}" "/t/g.sh=$d/g.sh" >"$d/mkfs.txt" 2>&1 || { bad "mkfs $pct"; return; }
    local sock="$d/q.sock" ACC=()
    [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
    timeout 300 qemu-system-x86_64 "${ACC[@]}" -kernel "$T/k0.img" -m 768 \
        -append "gfx disp wm wmdauer wmshell osum vfs bus fbres=$((xres*2))x$((yres*2)) vgpuheads vgpuextend script=sh /t/g.sh;exit" \
        -serial "file:$d/s.txt" -display none -no-reboot -vga std \
        -device virtio-gpu-pci,id=vg,max_outputs=2,xres=$xres,yres=$yres -global VGA.edid=off \
        -monitor "unix:$sock,server,nowait" -drive "file=$d/disk.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$d/q.txt" 2>&1 &
    local qp=$!
    waitfor() {
        local pat=$1 i=0
        while [ $i -lt 400 ]; do
            grep -qa "$pat" "$d/s.txt" 2>/dev/null && return 0
            kill -0 "$qp" 2>/dev/null || return 1
            sleep 0.5; i=$((i+1))
        done
        return 1
    }
    waitfor "scaledemo: box w=$((pct*100/100))"
    sleep 5
    for h in 0 1; do printf 'screendump %s/h%s.ppm vg %s\n' "$d" "$h" "$h" | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1; done
    sleep 3
    waitfor "taskbar: hotplug reapply"
    sleep 4
    printf 'quit\n' | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1
    wait "$qp" 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$d/s.txt" > "$d/s.klar"
    [ -n "${OUT:-}" ] && mkdir -p "$OUT" && cp -f "$d/s.klar" "$OUT/s$pct.klar" && cp -f "$d"/h0.ppm "$OUT/h0_$pct.ppm" && cp -f "$d"/h1.ppm "$OUT/h1_$pct.ppm" 2>/dev/null
    grep -a "^scaledemo: box\|^taskbar: hotplug" "$d/s.klar" | sed 's/^/   /'
    local bw=$pct bh=$((pct*40/100)) sm=$((pct*10)) inx=$((2*pct/100)) iny=$((22*pct/100))
    [ "$pct" = 150 ] && inx=3 && iny=33
    has "$d/s.klar" "^scaledemo: box w=100 h=40 sm=1000" "$pct: head 0 window: 100 percent, box 100x40"
    has "$d/s.klar" "^scaledemo: box w=$bw h=$bh sm=$sm" "$pct: head 1 window: $pct percent exact, box ${bw}x${bh}"
    has "$d/s.klar" "^scaledemo: box w=100 h=40 sm=1000 pct=100 inx=2 iny=22" "$pct: head 0 frame: border 2, title bar 22 (100 percent)"
    has "$d/s.klar" "^scaledemo: box w=$bw h=$bh sm=$sm pct=$pct inx=$inx iny=$iny" "$pct: head 1 frame: border $inx, title bar $iny"
    has "$d/s.klar" "^taskbar: hotplug reapply new=2" "$pct: head 1 plugged in after login: layout re-applied"
    for h in 0 1; do python3 -I tools/monscale/box.py "$d/h$h.ppm" > "$d/b$h.txt" 2>/dev/null || echo "0 0" > "$d/b$h.txt"; done
    [ "$(cat "$d/b0.txt")" = "100 40" ] && ok "$pct: pixels head 0: magenta box 100x40" || bad "$pct: pixels head 0: $(cat "$d/b0.txt")"
    [ "$(cat "$d/b1.txt")" = "$bw $bh" ] && ok "$pct: pixels head 1: magenta box ${bw}x${bh}" || bad "$pct: pixels head 1: $(cat "$d/b1.txt")"
}

mon() {
    local sock=$1 line
    shift
    for line in "$@"; do
        printf '%s\n' "$line" | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1
        sleep 0.25
    done
}

run_drag() {
    local d="$T/drag"
    mkdir -p "$d"
    printf 'heads=extend\nhead1=0,480,150\n' > "$d/displays.conf"
    printf 'orientbus serve 0 &\nsleep -m 300\naxd serve 0 &\nsleep 1\ntaskbar &\nsleep 8\nscaledemo 100 20 1 &\nsleep 150\necho ==B-END==\n' > "$d/g.sh"
    local A=(build "$d/disk.img" 32768 --v3 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /var/ /var/log/
       /etc/ /etc/actions.d/ /etc/orientbus/
       "/etc/actions.d/a11y.actions=etc/actions.d/a11y.actions" "/etc/orientbus/policy=etc/orientbus/policy"
       "/etc/uitrace=$T/uitrace" "/etc/taskbar.conf=$T/taskbar.conf" "/etc/displays.conf=$d/displays.conf" /etc/schemas/
       /usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/en/ "/usr/share/locale/en/messages=locale/en/messages")
    [ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
    local s p
    for s in assets/schemes/*.scheme; do A+=("/etc/schemas/$(basename "$s" .scheme)=$s"); done
    for p in $PROGS; do A+=("/bin/$p=$T/bin/$p.elf"); done
    bash tools/mkfsfi/mkfs.sh "${A[@]}" "/t/g.sh=$d/g.sh" >"$d/mkfs.txt" 2>&1 || { bad "mkfs drag"; return; }
    local sock="$d/q.sock" ACC=()
    [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
    timeout 300 qemu-system-x86_64 "${ACC[@]}" -kernel "$T/k0.img" -m 768 \
        -append "gfx disp wm wmdauer wmshell osum vfs bus fbres=1280x960 vgpuheads vgpuextend script=sh /t/g.sh;exit" \
        -serial "file:$d/s.txt" -display none -no-reboot -vga std \
        -device virtio-gpu-pci,id=vg,max_outputs=2,xres=640,yres=480 -global VGA.edid=off \
        -monitor "unix:$sock,server,nowait" -drive "file=$d/disk.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$d/q.txt" 2>&1 &
    local qp=$!
    local i=0
    while [ $i -lt 400 ] && ! grep -qa "taskbar: hotplug reapply new=2" "$d/s.txt" 2>/dev/null; do
        kill -0 "$qp" 2>/dev/null || break
        sleep 0.5; i=$((i+1))
    done
    sleep 3
    mon "$sock" "mouse_move -120 -120" "mouse_move -120 -120" "mouse_move -120 -120" "mouse_move -120 -120" "mouse_move -120 -120" "mouse_move -120 -120" \
        "mouse_move 120 0" "mouse_move 30 31"
    sleep 1
    mon "$sock" "mouse_button 1"
    sleep 1
    mon "$sock" "mouse_move 0 120" "mouse_move 0 120" "mouse_move 0 120" "mouse_move 0 100"
    sleep 3
    tr -cd '\11\12\15\40-\176' < "$d/s.txt" > "$d/held1.klar"
    mon "$sock" "mouse_button 0"
    sleep 2
    mon "$sock" "mouse_button 1"
    sleep 1
    mon "$sock" "mouse_move 0 -120" "mouse_move 0 -120" "mouse_move 0 -120" "mouse_move 0 -120"
    sleep 3
    tr -cd '\11\12\15\40-\176' < "$d/s.txt" > "$d/held2.klar"
    mon "$sock" "mouse_button 0"
    sleep 2
    printf 'quit\n' | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1
    wait "$qp" 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$d/s.txt" > "$d/s.klar"
    [ -n "${OUT:-}" ] && mkdir -p "$OUT" && cp -f "$d/s.klar" "$OUT/sdrag.klar"
    grep -a "^wm: fscale\|^scaledemo: box" "$d/s.klar" | sed 's/^/   /'
    has "$d/held1.klar" "^wm: fscale i=[0-9]* pct=150" "drag: frame scale 150 applied while the button is still held (head 1)"
    has "$d/held1.klar" "^scaledemo: box w=150 h=60 sm=1500 pct=150 inx=3 iny=33" "drag: client re-laid out at 150 percent during the drag"
    has "$d/held2.klar" "^wm: fscale i=[0-9]* pct=100" "drag back: frame scale 100 applied while the button is still held (head 0)"
    local n150 n100
    n150=$(grep -ac "^wm: fscale i=[0-9]* pct=150" "$d/s.klar")
    n100=$(grep -ac "^wm: fscale i=[0-9]* pct=100" "$d/s.klar")
    [ "$n150" = 1 ] && [ "$n100" = 1 ] && ok "drag: exactly one scale change per head crossing (no flip-flop)" || bad "drag: scale changes 150:$n150 100:$n100"
}
OUT="${1:-}"
[ "${MONSCALE_ONLY:-}" = drag ] || run_case 150 640 480 "100 520"
[ "${MONSCALE_ONLY:-}" = drag ] || run_case 200 1024 768 "100 808"
[ "${MONSCALE_ONLY:-}" = cases ] || run_drag
echo "monscale: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
