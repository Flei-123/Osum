#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vgpuheads/run.sh -- r808 multi-monitor, kernel step 1: output table + mirror.
#
# WHAT IT MEASURES (QEMU, virtio-gpu with max_outputs=2, then max_outputs=1)
#   1. The vgpu driver reads ALL connected heads into its output table
#      (`vgpu: ... heads=N`).
#   2. Every extra connected head is switched to the primary resource
#      (SET_SCANOUT id>=1): `mirr=1 merr=0` with two heads.
#   2b. Every connected head: GET_EDID parsed (maker, preferred mode, mm size, scale).
#   3. SCREEN PROOF, not just a counter: `screendump` of head 1 has the size of head 0 and is byte-identical
#      to head 0 (mirror); the control without the test-bed word leaves head 1 at QEMU's placeholder.
#      NOT proven: that the picture is non-black -- the harness has no fonts/wm (kernel formats the ATA test
#      disk), the fbtest pattern lands on the VGA, not the vgpu. Counted in the report as open.
#   4. CONTROL: with max_outputs=1 the driver reports heads=1 mirr=0 and QEMU has
#      no head 1 to dump (the dump of head 1 must fail / be empty).
#
# NOT MEASURED: extend mode (needs a per-output compositor, later step).
#
# Usage: [VGPU_KERNEL=<kernel.elf>] bash tools/vgpuheads/run.sh   (builds its own kernel when unset)
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

run_case() { # run_case <tag> <max_outputs> [extra kernel words]
    local tag=$1 mo=$2 words=${3:-}
    cp -f "$T/d.img" "$T/$tag.img"
    local S="$T/$tag.sock"
    timeout 150 $QEMU_X86 -kernel "$K" -m 256 \
        -append "gfx disp nocursor fbtest fbhold $words nokbd nosched noproc nofs" \
        -serial "file:$T/$tag.txt" -display none -no-reboot \
        -vga std -device virtio-gpu-pci,id=vg,max_outputs=$mo -global VGA.edid=off \
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

ppm_size() { # file -> "WxH" from the P6 header
    python3 -I - "$1" <<'PYEOF'
import sys
d = open(sys.argv[1], 'rb').read(32).split(b'\n')
print(d[1].decode().replace(' ', 'x'))
PYEOF
}

echo "== two heads (max_outputs=2)"
run_case two 2 vgpuheads
L=$(grep -a '^vgpu: bdf' "$T/two.txt" | tail -1)
echo "   $L"
echo "$L" | grep -aq 'scanout=2' && ok "device reports 2 scanouts" || bad "device scanout count != 2"
echo "$L" | grep -aq 'heads=2' && ok "output table: 2 connected heads" || bad "heads != 2"
echo "$L" | grep -aq 'mirr=1  merr=0' && ok "head 1 mirrors the primary resource (mirr=1 merr=0)" || bad "mirror counters wrong"
EDRE='edid=[A-Z]{3} pref=[0-9]+x[0-9]+ mm=[0-9]+x[0-9]+ scale=(100|125|150|175|200|250|300)$'
for hd in 0 1; do
    grep -aE "^vgpu: head $hd [0-9]+x[0-9]+ $EDRE" "$T/two.txt" >/dev/null \
        && ok "head $hd: EDID read (maker, preferred mode, mm, scale): $(grep -aE "^vgpu: head $hd " "$T/two.txt" | cut -d' ' -f4-)" \
        || bad "head $hd: no valid EDID line"
done
[ -s "$T/two.h0.ppm" ] && ok "screendump head 0 written" || bad "no screendump of head 0"
[ -s "$T/two.h1.ppm" ] && ok "screendump head 1 written" || bad "no screendump of head 1"
if [ -s "$T/two.h0.ppm" ] && [ -s "$T/two.h1.ppm" ]; then
    S0=$(ppm_size "$T/two.h0.ppm"); S1=$(ppm_size "$T/two.h1.ppm")
    [ "$S0" = "$S1" ] && ok "head 1 has the size of head 0 ($S1)" || bad "head sizes differ ($S0 vs $S1)"
    cmp -s "$T/two.h0.ppm" "$T/two.h1.ppm" && ok "head 1 is byte-identical to head 0 (mirror)" || bad "head 1 differs from head 0"
fi

echo "== two heads, NOT mirrored (control: same machine, driver does not use head 1)"
run_case plain 2
L=$(grep -a '^vgpu: bdf' "$T/plain.txt" | tail -1)
echo "   $L"
echo "$L" | grep -aq 'scanout=2' && ok "plain: device still has 2 scanouts" || bad "plain: scanout count != 2"
echo "$L" | grep -aq 'heads=1  mirr=0' && ok "plain: QEMU (no GUI) flags only head 0 as enabled -> heads=1, nothing mirrored" || bad "plain: counters wrong"
if [ -s "$T/plain.h1.ppm" ]; then
    SP=$(ppm_size "$T/plain.h1.ppm")
    [ "$SP" != "$S1" ] && ok "plain: head 1 is NOT the mirrored picture (QEMU placeholder $SP, mirrored was ${S1:-?})" || bad "plain: head 1 looks mirrored without SET_SCANOUT"
fi

echo "== one head (control, max_outputs=1)"
run_case one 1 vgpuheads
L=$(grep -a '^vgpu: bdf' "$T/one.txt" | tail -1)
echo "   $L"
grep -aE "^vgpu: head 0 [0-9]+x[0-9]+ $EDRE" "$T/one.txt" >/dev/null && ok "control: head 0 EDID read" || bad "control: head 0 has no EDID"
grep -aq '^vgpu: head 1 ' "$T/one.txt" && bad "control: a head 1 line exists" || ok "control: no head 1 line"
echo "$L" | grep -aq 'heads=1' && ok "control: 1 head" || bad "control: heads != 1"
echo "$L" | grep -aq 'mirr=0  merr=0' && ok "control: nothing mirrored" || bad "control: mirror counters wrong"
if [ -s "$T/one.h1.ppm" ]; then bad "control: head 1 dump exists"; else ok "control: no head 1 to dump"; fi

echo "heads: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
