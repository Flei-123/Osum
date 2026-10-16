#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vgpuhw/run.sh -- virtio-gpu hardware paths in QEMU (16.10.2026, VM window / resolution / pointer work).
#
# WHAT IT MEASURES (QEMU only: virtio-gpu-pci next to -vga std, kernel word `vgpuhw`, test pattern from `fbtest`)
#   1. HOST RESIZE: QEMU is asked through VNC (SetDesktopSize -> dpy_set_ui_info, the path a GTK/SDL window drag takes) to make the
#      virtio-gpu display 1024x768. The kernel must see the config-change event, switch the mode (vmode.follow_host ->
#      vgpu.resize) and the screendump of the virtio-gpu head is then 1024x768 with the red square where the harness painted it.
#   2. DEVICE CURSOR: pointer moves go through the cursor queue (60 MOVE_CURSOR, 0 octets through the resource) and the screendump
#      holds NO pointer pixels (QEMU does not composite the device cursor into screendump).
#   3. DIRTY RECT: 60 frames with a 48x48 rect carry 60 * 9216 octets, not the screen (<= 64 KB per frame).
#   4. SAME PICTURE: the virtio-gpu head is byte-identical to the VGA head of the same kernel with `novgpu` (firmware framebuffer copy).
#   Controls (each MUST be detected by the matching check):
#      nohwcur  -> pointer is painted into the frame buffer: check 2 must fail (white pixels in the dump, octets in phase 1)
#      wmruhe   -> whole screen dirty every frame: check 3 must fail (> 64 KB per frame)
#      nostim   -> no resize request: check 1 must fail (screen stays 640x480)
#
# NOT PROVEN HERE: a real GTK/SDL window drag, VirtualBox/VMSVGA (different device), the desktop (wm) re-layout after a size change
# (only the kernel side + the frame buffer are checked), 2+ heads (tools/vgpuheads, tools/vgpuext).
#
# Usage: [VGPU_KERNEL=<kernel.elf-or-mb>] bash tools/vgpuhw/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh >/dev/null 2>&1
HERE=$(pwd)/tools/vgpuhw
if [ -n "${OUT:-}" ]; then mkdir -p "$OUT"; T=$OUT; else T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; fi
K=${VGPU_KERNEL:-$T/k.mb}
if [ -z "${VGPU_KERNEL:-}" ]; then
    bash tools/build-kernel.sh "$K" >"$T/build.log" 2>&1 || { echo "build failed"; tail -20 "$T/build.log"; exit 1; }
fi
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

python3 tools/osum/mkfs.py build "$T/d.img" 4096 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf >/dev/null 2>&1

# run_case <tag> <words> <stim: 1 = ask QEMU for 1024x768 after "vgpuhw: ready">
run_case() {
    local tag=$1 words=$2 stim=$3
    cp -f "$T/d.img" "$T/$tag.img"
    local S="$T/$tag.sock" V="$T/$tag.vnc"
    timeout 150 $QEMU_X86 -kernel "$K" -m 256 \
        -append "gfx disp nocursor fbtest fbhold $words nokbd nosched noproc nofs" \
        -serial "file:$T/$tag.txt" -display none -no-reboot \
        -vga std -device virtio-gpu-pci,id=vg,xres=640,yres=480 -global VGA.edid=off \
        -vnc "unix:$V,display=vg" \
        -monitor "unix:$S,server,nowait" \
        -drive "file=$T/$tag.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$T/$tag.qemu" 2>&1 &
    local pid=$!
    local i=0
    while [ $i -lt 1000 ]; do
        grep -qaE "^vgpuhw: (ready|novgpu)" "$T/$tag.txt" 2>/dev/null && break
        kill -0 $pid 2>/dev/null || break
        sleep 0.15; i=$((i+1))
    done
    python3 -I - "$S" "$T/$tag" "$stim" "$HERE" "$V" "$T/$tag.txt" <<'PYEOF'
import os, socket, subprocess, sys, time
sock, base, stim, here, vnc, serial = sys.argv[1:7]
s = socket.socket(socket.AF_UNIX)
try:
    s.connect(sock)
except OSError:
    sys.exit(0)
s.settimeout(3.0)
time.sleep(0.3)
try: s.recv(65536)
except OSError: pass

def dump(name, dev):
    f = "%s.%s.ppm" % (base, name)
    s.sendall(("screendump %s %s\n" % (f, dev)).encode())
    last = -1
    end = time.time() + 8
    while time.time() < end:
        try: g = os.path.getsize(f)
        except OSError: g = -1
        if g > 0 and g == last: break
        last = g; time.sleep(0.25)
    try: s.recv(65536)
    except OSError: pass

def have(txt):
    try: return txt in open(serial, errors="replace").read()
    except OSError: return False

dump("vg0", "vg")          # virtio-gpu head before any resize
dump("vga0", "")           # the VGA head (reference when the driver is off)
if stim == "1":
    subprocess.run([sys.executable, "-I", os.path.join(here, "vncresize.py"), vnc, "1024", "768"], timeout=30)
    end = time.time() + 20
    while time.time() < end and not have("vgpuhw: panel=1024x768"):
        time.sleep(0.3)
    time.sleep(1.0)
    dump("vg1", "vg")      # virtio-gpu head after the resize
s.close()
PYEOF
    wait $pid 2>/dev/null
}

ppm_size() { python3 -I - "$1" <<'PYEOF'
import sys
d = open(sys.argv[1], 'rb').read(32).split(b'\n')
print(d[1].decode().replace(' ', 'x'))
PYEOF
}
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
# number of pure white pixels in the pointer strip (x 290..500, y 295..320)
whites() { python3 -I - "$1" <<'PYEOF'
import sys
d = open(sys.argv[1], 'rb').read()
parts = d.split(b'\n', 3)
w, h = map(int, parts[1].split())
body = parts[3]
n = 0
for y in range(295, 320):
    for x in range(290, 500):
        o = (y * w + x) * 3
        if body[o] == 255 and body[o+1] == 255 and body[o+2] == 255:
            n += 1
print(n)
PYEOF
}
num() { # num <file> <pattern with one \(group\)> -> last match
    grep -a "$2" "$1" | tail -1 | sed -n "s/$2/\1/p"
}

echo "== main: virtio-gpu, device cursor, host resize via VNC"
run_case main "vgpuhw" 1
M="$T/main.txt"
grep -a '^vgpuhw:\|^vgpu: hw' "$M" | sed 's/^/   /'
grep -aq '^vgpuhw: move hw=1 ' "$M" && ok "device cursor available (cursorq up)" || bad "no device cursor"
MV=$(num "$M" '^vgpuhw: move hw=1 moves=\([0-9]*\) okt=[0-9]*')
MO=$(num "$M" '^vgpuhw: move hw=1 moves=[0-9]* okt=\([0-9]*\)')
[ "${MV:-0}" -ge 59 ] && ok "60 pointer moves went through MOVE_CURSOR ($MV)" || bad "MOVE_CURSOR count ${MV:-none} < 59"
[ "${MO:-1}" = "0" ] && ok "pointer moves cost 0 octets through the resource" || bad "pointer moves cost ${MO:-?} octets"
PF=$(num "$M" '^vgpuhw: frames hw=1 okt=[0-9]* perframe=\([0-9]*\)')
if [ -n "$PF" ]; then
    echo "   octets per frame (48x48 dirty rect): $PF"
    [ "$PF" -le 65536 ] && ok "dirty rect carried, not the screen: $PF octets/frame (<= 65536)" || bad "$PF octets/frame > 64 KB"
    [ "$PF" -eq 9216 ] && ok "exactly the rect: 48*48*4 = 9216 octets/frame" || bad "octets/frame $PF != 9216"
else
    bad "no frames line"
fi
if [ -s "$T/main.vg0.ppm" ]; then
    W0=$(whites "$T/main.vg0.ppm")
    [ "$W0" -eq 0 ] && ok "screendump has NO pointer pixels (device cursor, not painted)" || bad "$W0 white pointer pixels in the dump"
    [ "$(ppm_size "$T/main.vg0.ppm")" = "800x600" ] && ok "start size 800x600 (fbtest default; the device asks 640x480, the host size is not applied at boot)" || bad "start size $(ppm_size "$T/main.vg0.ppm")"
else bad "no screendump before resize"; fi
grep -aq '^vgpuhw: panel=1024x768' "$M" && ok "kernel followed the host: panel 1024x768" || bad "kernel did not reach 1024x768"
grep -aq '^vgpu: hw rsz=[1-9][0-9]* rszerr=0 ' "$M" && ok "vgpu.resize ran (rsz>=1, rszerr=0)" || bad "vgpu.resize counters wrong: $(grep -a '^vgpu: hw' "$M" | tail -1)"
if [ -s "$T/main.vg1.ppm" ]; then
    S1=$(ppm_size "$T/main.vg1.ppm")
    [ "$S1" = "1024x768" ] && ok "screendump of the virtio-gpu head is 1024x768 after the host resize" || bad "dump size after resize $S1"
    [ "$(px "$T/main.vg1.ppm" 50 50)" = "ff0000" ] && ok "red square at (50,50) after the resize (resource carries the new frame)" || bad "(50,50) = $(px "$T/main.vg1.ppm" 50 50)"
    [ "$(px "$T/main.vg1.ppm" 900 700)" = "000000" ] && ok "new area (900,700) is black, no garbage" || bad "(900,700) = $(px "$T/main.vg1.ppm" 900 700)"
else bad "no screendump after resize"; fi

echo "== reference: same kernel, driver off (novgpu) -> firmware framebuffer copy"
run_case ref "vgpuhw novgpu" 0
if [ -s "$T/ref.vga0.ppm" ] && [ -s "$T/main.vg0.ppm" ]; then
    # the serial console is mirrored as text below the pattern (different lines per run): compare the pattern area, rows 0..239
    DIFFN=$(python3 -I - "$T/ref.vga0.ppm" "$T/main.vg0.ppm" <<'PYEOF'
import sys
def rd(f):
    d = open(f, 'rb').read(); p = d.split(b'\n', 3); w, h = map(int, p[1].split()); return w, h, p[3]
a = rd(sys.argv[1]); b = rd(sys.argv[2])
if a[:2] != b[:2]:
    print(-1); sys.exit()
n = a[0] * 240 * 3
print(sum(1 for i in range(0, n, 3) if a[2][i:i+3] != b[2][i:i+3]))
PYEOF
)
    [ "$DIFFN" = "0" ] && ok "virtio-gpu head equals the novgpu VGA reference in the pattern area (rows 0..239, 0 differing pixels)" \
        || bad "virtio-gpu head differs from the novgpu reference ($DIFFN pixels)"
else bad "reference dumps missing"; fi

echo "== control nohwcur: pointer painted into the frame buffer -> checks must see it"
run_case cur "vgpuhw nohwcur" 0
CO=$(num "$T/cur.txt" '^vgpuhw: move hw=0 moves=[0-9]* okt=\([0-9]*\)')
CW=$(whites "$T/cur.vga0.ppm" 2>/dev/null); CV=$(whites "$T/cur.vg0.ppm" 2>/dev/null)
echo "   software pointer: phase-1 octets ${CO:-?}, white pixels in virtio-gpu dump ${CV:-?}"
[ "${CO:-0}" -gt 0 ] && ok "control: software pointer costs octets in the resource (${CO})" || bad "control: no octets with nohwcur"
[ "${CV:-0}" -gt 0 ] && ok "control: pointer pixels ARE in the dump (the pointer check would FAIL)" || bad "control: dump has no pointer pixels"

echo "== control wmruhe: whole screen dirty every frame"
run_case ruhe "vgpuhw wmruhe" 0
RF=$(num "$T/ruhe.txt" '^vgpuhw: frames hw=[01] okt=[0-9]* perframe=\([0-9]*\)')
echo "   octets per frame: ${RF:-?}"
[ "${RF:-0}" -gt 65536 ] && ok "control: ${RF} octets/frame > 64 KB (the dirty-rect check would FAIL)" || bad "control: wmruhe not above 64 KB (${RF:-none})"

echo "== control nostim: no resize request"
run_case nost "vgpuhw" 0
if grep -aq '^vgpuhw: panel=' "$T/nost.txt"; then bad "control: kernel changed size without a host request"
else ok "control: no request, no size change (resize check would FAIL)"; fi

echo "vgpuhw: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
