#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/setheads/run.sh -- G-007: the Settings monitors page lists the connected outputs (size, scale percent when not 100, from the window server).
#
#   /root/jarvis/bin/heavy bash tools/setheads/run.sh [<outdir>]
#
# QEMU with two 640x480 outputs (vgpuheads vgpuextend): `settings page=32` must report both outputs; the control with ONE output lists one.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
. tools/lib/qemu.sh >/dev/null 2>&1
OUT=${1:-}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[ -n "$OUT" ] && mkdir -p "$OUT"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaE -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }

. tools/lib/firnenv.sh
mkdir -p "$T/bin"
PROGS="sh ls cat echo sleep orientbus act axd settings taskbar"
HOOK=""
if bash tools/sync/build.sh "$T/bin" 0 $PROGS >"$T/b.txt" 2>&1 \
   && ./tools/build-kernel.sh "$T/k0.img" --stufe 0 >"$T/k.txt" 2>&1; then
    ok "programs and kernel build"
else
    bad "build failed"; tail -8 "$T/b.txt" "$T/k.txt" | sed 's/^/        /'
    echo "setheads: $pass ok, $fail fail"; exit 1
fi

mkscript() {
    cat > "$T/$1" <<EOS
orientbus serve 0 &
sleep -m 300
axd serve 0 &
sleep 1
settings page=32 $2 &
sleep 60
echo ==B-END==
EOS
}
cat > "$T/g4.sh" <<'EOS'
orientbus serve 0 &
sleep -m 300
axd serve 0 &
sleep 1
taskbar &
sleep 8
settings page=32 &
sleep 40
echo ==B-END==
EOS
printf 'edge=bottom\nheight=40\nwidth=104\nautohide=0\nontop=1\nalign=center\nlabels=never\npins=explorer,calc\n' > "$T/taskbar.conf"
printf 'heads=extend\nhead1=0,480,125\n' > "$T/displays.conf"
mkscript g2.sh "hotplug=1"
mkscript g3.sh ""
cat > "$T/g.sh" <<'EOS'
orientbus serve 0 &
sleep -m 300
axd serve 0 &
sleep 1
settings page=32 &
sleep 60
echo ==B-END==
EOS
printf 'on\n' > "$T/uitrace"
printf '# /etc/theme.conf\nscheme=night\nmode=dark\naccent=\nshape=modern\n' > "$T/theme.conf"
A=(build "$T/disk.img" 32768 --v3 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf"
   "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /var/ /var/log/
   /etc/ /etc/actions.d/ /etc/orientbus/
   "/etc/actions.d/a11y.actions=etc/actions.d/a11y.actions"
   "/etc/orientbus/policy=etc/orientbus/policy"
   "/etc/uitrace=$T/uitrace" "/etc/taskbar.conf=$T/taskbar.conf" "/etc/displays.conf=$T/displays.conf" "/etc/theme.conf=$T/theme.conf" /etc/schemas/
   /usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/en/ "/usr/share/locale/en/messages=locale/en/messages")
[ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
for s in assets/schemes/*.scheme; do A+=("/etc/schemas/$(basename "$s" .scheme)=$s"); done
for p in $PROGS; do A+=("/bin/$p=$T/bin/$p.elf"); done
bash tools/mkfsfi/mkfs.sh "${A[@]}" "/t/g.sh=$T/g.sh" "/t/g2.sh=$T/g2.sh" "/t/g3.sh=$T/g3.sh" "/t/g4.sh=$T/g4.sh" >"$T/mkfs.txt" 2>&1 || { bad "mkfs"; tail -3 "$T/mkfs.txt"; echo "setheads: $pass ok, $fail fail"; exit 1; }

run_case() { # run_case <tag> <max_outputs> <words> [<xres> <yres>]
    local tag=$1 mo=$2 words=$3 xr=${4:-640} yr=${5:-480}
    local sock="$T/$tag.sock"
    cp -f "$T/disk.img" "$T/$tag.img"
    ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
    timeout 330 qemu-system-x86_64 "${ACC[@]}" -kernel "$T/k0.img" -m 768 \
        -append "gfx disp wm wmdauer ${RC_SHELL-wmshell} osum vfs bus $words script=sh /t/${RC_SCRIPT:-g.sh};exit" \
        -serial "file:$T/$tag.txt" -display none -no-reboot \
        -vga std -device virtio-gpu-pci,id=vg,max_outputs=$mo,xres=$xr,yres=$yr -global VGA.edid=off \
        -monitor "unix:$sock,server,nowait" \
        -drive "file=$T/$tag.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$T/$tag.q" 2>&1 &
    local qp=$! i=0
    while [ $i -lt 900 ]; do
        wn=$(grep -acE "${RC_WAIT:-^settings: heads }" "$T/$tag.txt" 2>/dev/null || true)
        [ "${wn:-0}" -ge "${RC_WAITN:-1}" ] && break
        kill -0 "$qp" 2>/dev/null || break
        sleep 0.3; i=$((i+1))
    done
    sleep 6
    [ -n "${RC_HOOK:-}" ] && "$RC_HOOK" "$tag" "$sock"
    printf 'screendump %s/%s-h0.ppm vg 0\n' "$T" "$tag" | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1
    sleep 4
    printf 'quit\n' | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1
    wait "$qp" 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$T/$tag.txt" > "$T/$tag.klar"
    python3 -I tools/osum/mkfs.py cat "$T/$tag.img" /etc/displays.conf > "$T/$tag.conf" 2>/dev/null || true
    if [ -f "$T/$tag-h0.ppm" ]; then
        python3 -I - "$T/$tag-h0.ppm" "$T/$tag.png" <<'PY' 2>/dev/null
import sys
from PIL import Image
Image.open(sys.argv[1]).save(sys.argv[2])
PY
        [ -n "$OUT" ] && [ -f "$T/$tag.png" ] && cp -f "$T/$tag.png" "$OUT/$tag.png"
    fi
}

if [ -z "${SETHEADS_ONLY:-}" ]; then
echo "== two outputs"
run_case two 2 "fbres=1280x480 vgpuheads vgpuextend"
G="$T/two.klar"
grep -a "^settings: heads " "$G" | tail -1 | sed 's/^/   /'
has "$G" "^settings: heads Detected: 1: 640x480  2: 640x480 *$" "monitors page lists both outputs with size"
[ "$(grep -ac '^settings: ready ' "$G")" -ge 1 ] && ok "settings window opened" || bad "settings window did not open"

echo "== scale 2: two 1280x800 outputs"
run_case two2 2 "fbres=2560x800 vgpuheads vgpuextend uiscale=2" 1280 800
G="$T/two2.klar"
grep -a "^settings: heads " "$G" | tail -1 | sed 's/^/   /'
has "$G" "^settings: heads Detected: 1: 1280x800  2: 1280x800 *$" "scale 2: both outputs listed"

echo "== control: one output"
run_case one 1 "fbres=640x480"
G="$T/one.klar"
grep -a "^settings: heads " "$G" | tail -1 | sed 's/^/   /'
has "$G" "^settings: heads Detected: 1: 640x480 *$" "one output: exactly one entry"
grep -qaE "^settings: heads Detected: 1:.* 2: " "$G" && bad "one output: a second entry appeared" || ok "one output: no second entry"

fi

. tools/setheads/arrange.sh

echo "setheads: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
