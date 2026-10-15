#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vgpuext/run.sh -- r815 EXTEND + r819 head content is not black.
#
# WHAT IT MEASURES (QEMU, virtio-gpu max_outputs=2, heads 640x480, desktop res=1280x480)
#   1. Word `vgpuextend`: the vgpu driver lays the two heads out left to right
#      (lib/monitors/layout.fi pack_row rule) and scans each head out of ITS OWN RECT of the one wide
#      desktop resource: `ext=1 extp=2 exte=0 extc=0`, `ext head 0 rect=0,0 640x480`, `ext head 1 rect=640,0 640x480`.
#   2. SCREEN PROOF by screendump of both heads (pixel values, not counters):
#      head 0 shows the test pattern (red square + its own magenta box), head 1 shows ONLY its own
#      cyan box (not the red square, not the magenta box) and is NOT black.
#   3. r819 (mirror is not black): without `vgpuextend` both heads show the whole desktop incl. the red
#      square, identical, non-black.
#   4. CONTROLS: one head + vgpuextend -> ext=0 and the head shows the whole desktop; extend with a
#      desktop too small for head 1 (fbres=800x480) -> head 1 is cut/skipped, counted in extc.
#
# Usage: [VGPU_KERNEL=<kernel.mb>] bash tools/vgpuext/run.sh   (builds its own kernel when unset)
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh >/dev/null 2>&1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
K=${VGPU_KERNEL:-$T/k.mb}
if [ -z "${VGPU_KERNEL:-}" ]; then
    bash tools/build-kernel.sh "$K" >"$T/build.log" 2>&1 || { echo "build failed"; tail -20 "$T/build.log"; exit 1; }
fi
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

python3 tools/osum/mkfs.py build "$T/d.img" 4096 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf >/dev/null 2>&1

run_case() { # run_case <tag> <max_outputs> <res> [extra kernel words]
    local tag=$1 mo=$2 res=$3 words=${4:-}
    local resarg="fbres=$res"
    [ "$res" = "auto" ] && resarg=""
    cp -f "$T/d.img" "$T/$tag.img"
    local S="$T/$tag.sock"
    timeout 150 $QEMU_X86 -kernel "$K" -m 256 \
        -append "gfx disp nocursor fbtest fbhold $resarg $words nokbd nosched noproc nofs" \
        -serial "file:$T/$tag.txt" -display none -no-reboot \
        -vga std -device virtio-gpu-pci,id=vg,max_outputs=$mo,xres=640,yres=480 -global VGA.edid=off \
        -monitor "unix:$S,server,nowait" \
        -drive "file=$T/$tag.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$!
    local i=0
    while [ $i -lt 800 ]; do
        grep -qaE "^fb: hold" "$T/$tag.txt" 2>/dev/null && break
        kill -0 $pid 2>/dev/null || break
        sleep 0.15; i=$((i+1))
    done
    python3 -I - "$S" "$T/$tag" <<'PYEOF'
import os, socket, sys, time
sock, base = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX)
try:
    s.connect(sock)
except OSError:
    sys.exit(0)
s.settimeout(3.0)
time.sleep(0.4)
try: s.recv(65536)
except OSError: pass
for head in (0, 1):
    f = "%s.h%d.ppm" % (base, head)
    s.sendall(("screendump %s vg %d\n" % (f, head)).encode())
    last = -1
    end = time.time() + 6
    while time.time() < end:
        try: g = os.path.getsize(f)
        except OSError: g = -1
        if g > 0 and g == last: break
        last = g; time.sleep(0.25)
    try: s.recv(65536)
    except OSError: pass
s.close()
PYEOF
    wait $pid 2>/dev/null
}

# px <ppm> <x> <y>  -> "RRGGBB";  info <ppm> -> "WxH nonblack_percent"
px() { python3 -I - "$1" "$2" "$3" <<'PYEOF'
import sys
d = open(sys.argv[1], 'rb').read()
parts = d.split(b'\n', 3)
w, h = map(int, parts[1].split())
body = parts[3]
x, y = int(sys.argv[2]), int(sys.argv[3])
o = (y * w + x) * 3
print("%02x%02x%02x" % tuple(body[o:o+3]))
PYEOF
}
info() { python3 -I - "$1" <<'PYEOF'
import sys
d = open(sys.argv[1], 'rb').read()
parts = d.split(b'\n', 3)
w, h = map(int, parts[1].split())
body = parts[3]
n = sum(1 for i in range(0, len(body), 3) if body[i] or body[i+1] or body[i+2])
print("%dx%d %d" % (w, h, (100 * n) // max(1, w * h)))
PYEOF
}

RED=ff0000; MAG=ff00ff; CYAN=00ffff; BLACK=000000

echo "== extend, two heads (640x480 each), desktop 1280x480"
run_case ext 2 1280x480 "vgpuheads vgpuextend"
L=$(grep -a '^vgpu: bdf' "$T/ext.txt" | tail -1); echo "   $L"
echo "$L" | grep -aq 'heads=2' && ok "2 connected heads" || bad "heads != 2"
echo "$L" | grep -aq 'ext=1  extp=2  exte=0  extc=0' && ok "extend active: 2 heads placed, 0 refusals, 0 cut" || bad "extend counters wrong"
echo "$L" | grep -aq 'mirr=0' && ok "nothing mirrored in extend" || bad "extend also mirrored"
grep -aq '^vgpu: ext head 0 rect=0,0 640x480$' "$T/ext.txt" && ok "head 0 rect 0,0 640x480" || bad "head 0 rect line missing"
grep -aq '^vgpu: ext head 1 rect=640,0 640x480$' "$T/ext.txt" && ok "head 1 rect 640,0 640x480 (pack_row: right of head 0)" || bad "head 1 rect line missing"
if [ -s "$T/ext.h0.ppm" ] && [ -s "$T/ext.h1.ppm" ]; then
    I0=$(info "$T/ext.h0.ppm"); I1=$(info "$T/ext.h1.ppm")
    echo "   head0 $I0 % nonblack, head1 $I1 % nonblack"
    [ "${I0%% *}" = "640x480" ] && ok "head 0 dump is 640x480" || bad "head 0 dump size ${I0%% *}"
    [ "${I1%% *}" = "640x480" ] && ok "head 1 dump is 640x480" || bad "head 1 dump size ${I1%% *}"
    [ "${I1##* }" -ge 1 ] && ok "head 1 is NOT black (${I1##* } % lit)" || bad "head 1 is black"
    [ "$(px "$T/ext.h0.ppm" 50 50)" = "$RED" ] && ok "head 0 (50,50) = red square of the test pattern" || bad "head 0 (50,50) = $(px "$T/ext.h0.ppm" 50 50)"
    [ "$(px "$T/ext.h0.ppm" 180 200)" = "$MAG" ] && ok "head 0 (180,200) = its own magenta box" || bad "head 0 box = $(px "$T/ext.h0.ppm" 180 200)"
    [ "$(px "$T/ext.h1.ppm" 180 200)" = "$CYAN" ] && ok "head 1 (180,200) = its own cyan box" || bad "head 1 box = $(px "$T/ext.h1.ppm" 180 200)"
    [ "$(px "$T/ext.h1.ppm" 50 50)" = "$BLACK" ] && ok "head 1 (50,50) is black: no red square (not a mirror)" || bad "head 1 (50,50) = $(px "$T/ext.h1.ppm" 50 50)"
    ! cmp -s "$T/ext.h0.ppm" "$T/ext.h1.ppm" && ok "head 1 differs from head 0" || bad "heads identical in extend"
else
    bad "screendumps missing"
fi

echo "== mirror (r819), same machine without vgpuextend"
run_case mir 2 1280x480 "vgpuheads"
L=$(grep -a '^vgpu: bdf' "$T/mir.txt" | tail -1); echo "   $L"
echo "$L" | grep -aq 'ext=0' && ok "mirror: extend off" || bad "mirror: ext != 0"
if [ -s "$T/mir.h0.ppm" ] && [ -s "$T/mir.h1.ppm" ]; then
    I0=$(info "$T/mir.h0.ppm"); I1=$(info "$T/mir.h1.ppm")
    echo "   head0 $I0 % nonblack, head1 $I1 % nonblack"
    [ "${I0##* }" -ge 1 ] && ok "mirror head 0 is not black" || bad "mirror head 0 black"
    [ "${I1##* }" -ge 1 ] && ok "mirror head 1 is not black" || bad "mirror head 1 black"
    [ "$(px "$T/mir.h1.ppm" 50 50)" = "$RED" ] && ok "mirror head 1 (50,50) = red square" || bad "mirror head 1 (50,50) = $(px "$T/mir.h1.ppm" 50 50)"
    cmp -s "$T/mir.h0.ppm" "$T/mir.h1.ppm" && ok "mirror heads byte-identical" || bad "mirror heads differ"
else
    bad "mirror screendumps missing"
fi

echo "== r827: desktop size derived from the heads (no fbres=)"
run_case auto 2 auto "vgpuheads vgpuextend"
L=$(grep -a '^vgpu: bdf' "$T/auto.txt" | tail -1); echo "   $L"
grep -aq '^fb: heads desk=1280x480$' "$T/auto.txt" && ok "fb sized 1280x480 from two 640x480 heads" || bad "no derived desk line"
echo "$L" | grep -aq 'ext=1  extp=2  exte=0  extc=0' && ok "derived size: extend active, nothing cut" || bad "derived size: extend counters wrong"
echo "$L" | grep -aq 'schirm=1280x480' && ok "resource is 1280x480" || bad "resource size wrong"

echo "== control: one head + vgpuextend"
run_case one 1 1280x480 "vgpuheads vgpuextend"
L=$(grep -a '^vgpu: bdf' "$T/one.txt" | tail -1); echo "   $L"
echo "$L" | grep -aq 'ext=0' && ok "one head: extend stays off (whole desktop on the head)" || bad "one head: ext != 0"
[ -s "$T/one.h0.ppm" ] && [ "$(px "$T/one.h0.ppm" 50 50)" = "$RED" ] && ok "one head shows the pattern" || bad "one head: no pattern"

echo "== control: desktop too small (fbres=800x480, head 1 would start at 640)"
run_case small 2 800x480 "vgpuheads vgpuextend"
L=$(grep -a '^vgpu: bdf' "$T/small.txt" | tail -1); echo "   $L"
echo "$L" | grep -aq 'ext=1  extp=2  exte=0  extc=1' && ok "head 1 cut to the 160 columns that exist (extc=1)" || bad "small desktop: counters wrong"
grep -aq '^vgpu: ext head 1 rect=640,0 160x480$' "$T/small.txt" && ok "head 1 rect 640,0 160x480" || bad "small: head 1 rect wrong"

echo "vgpuext: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
