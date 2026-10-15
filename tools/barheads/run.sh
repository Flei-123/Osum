#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/barheads/run.sh -- r828 TASKBAR PER HEAD (extends tools/wmheads).
#
# WHAT IT MEASURES (QEMU, virtio-gpu max_outputs=2, heads 640x480, extended desktop 1280x480, real /bin/taskbar)
#   1. the first bar (no `--head`) serves head 0: geom x=0 w=640, y=440 (40 high at the bottom of ITS head);
#   2. it starts a second bar for head 1 (`taskbar: head my=1 spawn`), and that one stands at x=640 w=640, same y;
#   3. every bar gets the work area of ITS head from the window server (WI_WORK*): 0,0 640x440 and 640,0 640x440;
#   (No pixel proof: QEMU's screendump of the virtio heads stays black for window-server output in this harness, also
#   on the single-head control, so the check is the window server's own numbers -- geometry and work areas.)
# COUNTER-CONTROL (one head, same program, max_outputs=1, no vgpuextend): ONE bar over the whole screen, no spawn.
#
# Usage: bash tools/barheads/run.sh   (builds its own kernel + taskbar)
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
   && bash tools/sync/build.sh "$T/barbin" 0 taskbar >"$T/b2.txt" 2>&1 \
   && ./tools/build-kernel.sh "$T/k0.img" --stufe 0 >"$T/k.txt" 2>&1; then
    ok "programs, taskbar and kernel build"
else
    bad "build failed"; tail -8 "$T/b.txt" "$T/b2.txt" "$T/k.txt" | sed 's/^/        /'
    echo "barheads: $pass ok, $fail fail"; exit 1
fi

cat > "$T/g.sh" <<'EOS'
orientbus serve 0 &
sleep -m 300
axd serve 0 &
sleep 1
taskbar &
sleep 40
echo ==B-END==
act stop
echo ==FERTIG==
EOS
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
   "/bin/taskbar=$T/barbin/taskbar.elf" "/t/g.sh=$T/g.sh")
[ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
printf '# /etc/theme.conf\nscheme=night\nmode=dark\naccent=\nshape=modern\n' > "$T/theme.conf"
A+=("/etc/theme.conf=$T/theme.conf" /etc/schemas/)
for s in assets/schemes/*.scheme; do A+=("/etc/schemas/$(basename "$s" .scheme)=$s"); done
for p in $PROGS; do A+=("/bin/$p=$T/bin/$p.elf"); done
python3 tools/osum/mkfs.py "${A[@]}" >"$T/mkfs.txt" 2>&1 || { bad "mkfs"; tail -3 "$T/mkfs.txt"; exit 1; }

run_case() { # run_case <tag> <max_outputs> <words>
    local tag=$1 mo=$2 words=$3
    local sock="$T/$tag.sock"
    cp -f "$T/disk.img" "$T/$tag.img"
    ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
    timeout 240 qemu-system-x86_64 "${ACC[@]}" -kernel "$T/k0.img" -m 768 \
        -append "gfx disp wm wmdauer wmshell osum vfs bus $words script=sh /t/g.sh;exit" \
        -serial "file:$T/$tag.txt" -display none -no-reboot \
        -vga std -device virtio-gpu-pci,id=vg,max_outputs=$mo,xres=640,yres=480 -global VGA.edid=off \
        -monitor "unix:$sock,server,nowait" \
        -drive "file=$T/$tag.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$T/$tag.q" 2>&1 &
    local qp=$! i=0
    while [ $i -lt 600 ]; do
        grep -qaF "==B-END==" "$T/$tag.txt" 2>/dev/null && break
        kill -0 "$qp" 2>/dev/null || break
        sleep 0.3; i=$((i+1))
    done
    printf 'quit\n' | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1
    wait "$qp" 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$T/$tag.txt" > "$T/$tag.klar"
}

echo "== two heads: one bar per head"
run_case two 2 "fbres=1280x480 vgpuheads vgpuextend"
G="$T/two.klar"
grep -a "^taskbar: geom \|^taskbar: work \|^taskbar: head \|^wm: head " "$G" | sort -u | head -30 | sed 's/^/   /'
has "$G" '^taskbar: geom edge=0 x=0 y=440 w=640 h=40' "bar 0 stands at the bottom of head 0 (0,440 640x40)"
has "$G" '^taskbar: geom edge=0 x=640 y=440 w=640 h=40' "bar 1 stands at the bottom of head 1 (640,440 640x40)"
has "$G" '^taskbar: head my=1 spawn' "the first bar started a bar for head 1"
has "$G" '^taskbar: work +x=0 y=0 w=640 h=440' "bar 0 sees the work area of head 0 (0,0 640x440)"
has "$G" '^taskbar: work +x=640 y=0 w=640 h=440' "bar 1 sees the work area of head 1 (640,0 640x440)"
! grep -qaE '^taskbar: geom edge=0 x=0 y=440 w=1280' "$G" && ok "no bar spans both heads any more" || bad "a bar still spans 1280 px"

echo "== control: one head, same bar program"
run_case one 1 ""
G="$T/one.klar"
grep -a "^taskbar: geom \|^taskbar: head " "$G" | sort -u | head -6 | sed 's/^/   /'
SW=$(grep -aoE '^taskbar: geom edge=0 x=0 y=[0-9]+ w=[0-9]+' "$G" | tail -1 | sed 's/.* w=//')
[ -n "$SW" ] && [ "$SW" -ge 640 ] && ok "one head: one bar over the whole screen (w=$SW, x=0)" || bad "one head: bar geometry ($SW)"
! grep -qa 'taskbar: head my=' "$G" && ok "one head: no second bar" || bad "one head: a second bar was started"

echo "barheads: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
