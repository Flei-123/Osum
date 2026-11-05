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
cat > "$T/g.sh" <<'EOS'
orientbus serve 0 &
sleep -m 300
axd serve 0 &
sleep 1
taskbar &
sleep 8
scaledemo 100 20 1 &
scaledemo 100 520 0 &
sleep 150
echo ==B-END==
EOS
printf 'on\n' > "$T/uitrace"
printf 'edge=bottom\nheight=40\nwidth=104\nautohide=0\nontop=1\nalign=center\nlabels=never\npins=explorer,calc\n' > "$T/taskbar.conf"
printf 'heads=extend\nhead1=0,480,150\n' > "$T/displays.conf"
A=(build "$T/disk.img" 32768 --v3 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /var/ /var/log/
   /etc/ /etc/actions.d/ /etc/orientbus/
   "/etc/actions.d/a11y.actions=etc/actions.d/a11y.actions" "/etc/orientbus/policy=etc/orientbus/policy"
   "/etc/uitrace=$T/uitrace" "/etc/taskbar.conf=$T/taskbar.conf" "/etc/displays.conf=$T/displays.conf" /etc/schemas/
   /usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/en/ "/usr/share/locale/en/messages=locale/en/messages")
[ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
for s in assets/schemes/*.scheme; do A+=("/etc/schemas/$(basename "$s" .scheme)=$s"); done
for p in $PROGS; do A+=("/bin/$p=$T/bin/$p.elf"); done
bash tools/mkfsfi/mkfs.sh "${A[@]}" "/t/g.sh=$T/g.sh" >"$T/mkfs.txt" 2>&1 || { bad mkfs; exit 1; }
sock="$T/q.sock"
ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
timeout 300 qemu-system-x86_64 "${ACC[@]}" -kernel "$T/k0.img" -m 768 \
    -append "gfx disp wm wmdauer wmshell osum vfs bus fbres=1280x960 vgpuheads vgpuextend script=sh /t/g.sh;exit" \
    -serial "file:$T/s.txt" -display none -no-reboot -vga std \
    -device virtio-gpu-pci,id=vg,max_outputs=2,xres=640,yres=480 -global VGA.edid=off \
    -monitor "unix:$sock,server,nowait" -drive "file=$T/disk.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$T/q.txt" 2>&1 &
qp=$!
waitfor() {
    local pat=$1 i=0
    while [ $i -lt 400 ]; do
        grep -qa "$pat" "$T/s.txt" 2>/dev/null && return 0
        kill -0 "$qp" 2>/dev/null || return 1
        sleep 0.5; i=$((i+1))
    done
    return 1
}
waitfor "scaledemo: box w=150"
sleep 5
for h in 0 1; do printf 'screendump %s/h%s.ppm vg %s\n' "$T" "$h" "$h" | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1; done
sleep 3
waitfor "taskbar: hotplug reapply"
sleep 4
printf 'quit\n' | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1
wait "$qp" 2>/dev/null
tr -cd '\11\12\15\40-\176' < "$T/s.txt" > "$T/s.klar"
[ -n "${1:-}" ] && mkdir -p "$1" && cp -f "$T/s.klar" "$1/"
[ -n "${1:-}" ] && cp -f "$T"/h0.ppm "$T"/h1.ppm "$1/" 2>/dev/null
grep -a "^scaledemo: box\|^taskbar: hotplug" "$T/s.klar" | sed 's/^/   /'
has "$T/s.klar" "^scaledemo: box w=100 h=40 sm=1000" "head 0 window: 100 percent, box 100x40"
has "$T/s.klar" "^scaledemo: box w=150 h=60 sm=1500" "head 1 window: 150 percent exact, box 150x60"
has "$T/s.klar" "^taskbar: hotplug reapply new=2" "head 1 plugged in after login: layout re-applied"
for h in 0 1; do python3 -I tools/monscale/box.py "$T/h$h.ppm" > "$T/b$h.txt" 2>/dev/null || echo "0 0" > "$T/b$h.txt"; done
[ "$(cat "$T/b0.txt")" = "100 40" ] && ok "pixels head 0: magenta box 100x40" || bad "pixels head 0: $(cat "$T/b0.txt")"
[ "$(cat "$T/b1.txt")" = "150 60" ] && ok "pixels head 1: magenta box 150x60" || bad "pixels head 1: $(cat "$T/b1.txt")"
echo "monscale: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
