#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vmsvga/desktop.sh -- VMSVGA driver on the REAL desktop (stick image, Limine, -smp 4, -vga vmware), 16.10.2026.
#
# The testbed of tools/vmsvga/run.sh only paints its own test picture. VirtualBox showed broken rectangles on the real desktop, so
# this gate boots the real stick image, logs in and plays random mouse / key sequences (desktop.py). A tiny VNC client applies ONLY
# the rectangles the host was told about; after every sequence its picture must equal the screendump (VRAM, read directly).
#   case full  default (whole-screen UPDATE per frame)                         -> every compare 0
#   case rect  word `vmsvgarect` (dirty rectangles)                            -> every compare 0
#   case drop  words `vmsvgarect vmsvgadrop` (every 7th dirty note is lost)    -> MUST differ (negative control)
# Also: serial `vmsvga:` line says traces=0 (TRACES register written), and the VNC client really received rectangles.
#
# Usage: [STICK_DIR=<dir with orientos-usb.img>] [ROUNDS=8] bash tools/vmsvga/desktop.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
HERE=$(pwd)/tools/vmsvga
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
ROUNDS=${ROUNDS:-6}

if [ -n "${STICK_DIR:-}" ] && [ -f "$STICK_DIR/orientos-usb.img" ]; then
    IMG=$STICK_DIR/orientos-usb.img
else
    mkdir -p "$T/build"
    PARTTAB=mbr bash tools/usbimg/build.sh "$T/build" >"$T/build.log" 2>&1 || { echo "stick build failed"; tail -15 "$T/build.log"; exit 1; }
    IMG=$T/build/orientos-usb.img
fi

KVM=(-accel tcg)
[ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)

# run_case <tag> <extra kernel words> <seed>
run_case() {
    local tag=$1 words=$2 seed=$3
    local D=$T/$tag; mkdir -p "$D"
    cp -f "$IMG" "$D/stick.img"
    local off=$((2048 * 512))
    mcopy -o -i "$D/stick.img@@$off" ::/limine.conf "$D/l.conf" || return 1
    sed -i 's/^timeout: .*/timeout: 1/' "$D/l.conf"
    # the first (default) entry gets the extra words
    awk -v w="$words" 'BEGIN{d=0} /^ *cmdline:/ && d==0 { d=1; print $0 " " w; next } { print }' "$D/l.conf" >"$D/l2.conf"
    mcopy -o -i "$D/stick.img@@$off" "$D/l2.conf" ::/limine.conf
    timeout 700 qemu-system-x86_64 "${KVM[@]}" -m 2048 -smp 4 \
        -device qemu-xhci,id=xhci \
        -drive if=none,id=stick,format=raw,file="$D/stick.img" \
        -device usb-storage,bus=xhci.0,drive=stick,bootindex=1 \
        -netdev user,id=n0 -device e1000e,netdev=n0 \
        -vga vmware -vnc "unix:$D/vnc.sock" -display none -no-reboot \
        -serial file:"$D/serial.txt" \
        -monitor unix:"$D/mon.sock",server,nowait >"$D/qemu.txt" 2>&1 &
    local pid=$!
    python3 -I "$HERE/desktop.py" "$D/mon.sock" "$D/vnc.sock" "$D/o" "$D/serial.txt" "$seed" "$ROUNDS" 12 >"$D/py.txt" 2>&1 || true
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
}

# TOL: a fading hover or clock tail may still move a pixel or two between the VNC snapshot and the screendump (seen: one pixel
# 254 vs 255 in the taskbar). A lost window rectangle differs by hundreds of pixels, so a tolerance of 16 loses nothing.
TOL=${TOL:-16}
bad_rounds() { # <tag>: rounds with a real difference (diff > TOL)
    awk -v t="$TOL" '$2 > t { n++ } END { print n+0 }' "$T/$1/o.rounds" 2>/dev/null
}
good_rounds() { # <tag>: rounds with a stable compare (0 .. TOL differing pixels)
    awk -v t="$TOL" '$2 >= 0 && $2 <= t { n++ } END { print n+0 }' "$T/$1/o.rounds" 2>/dev/null
}

echo "== full-update way (default)"
run_case full "" 11
echo "== rectangle way (vmsvgarect)"
run_case rect "vmsvgarect" 12
echo "== control: rectangle way with every 7th note lost (vmsvgarect vmsvgadrop)"
run_case drop "vmsvgarect vmsvgadrop" 13

for c in full rect; do
    chk "$c: signed in on the real desktop" '[ "$(cat "$T/$c/o.login" 2>/dev/null)" = 1 ]'
    chk "$c: driver detected, TRACES register written (traces=0)" 'grep -a "^vmsvga: bdf=" "$T/$c/serial.txt" | head -1 | grep -q " traces=0"'
    chk "$c: VNC client got rectangles (updates > 20)" '[ "$(cat "$T/$c/o.updates" 2>/dev/null || echo 0)" -gt 20 ]'
    chk "$c: >= $((ROUNDS / 2)) stable compares, ALL equal to the screendump (<= $TOL px)" \
        '[ "$(good_rounds $c)" -ge $((ROUNDS / 2)) ] && [ "$(bad_rounds $c)" = 0 ]'
    chk "$c: the desktop loop presents (serial pulse: prs and pfr grow, upd > 20)" \
        'grep -a "^vmsvga: pulse" "$T/$c/serial.txt" | tail -1 | awk "{split(\$3,a,\"=\"); split(\$4,b,\"=\"); split(\$5,u,\"=\"); exit !(a[2] > 100 && b[2] > 3 && u[2] > 20)}"'
done
chk "control drop: signed in" '[ "$(cat "$T/drop/o.login" 2>/dev/null)" = 1 ]'
chk "control drop: the lost notes are SEEN (at least one compare differs)" '[ "$(bad_rounds drop)" -ge 1 ]'

echo "vmsvga desktop gate: $pass ok, $fail fail"
for c in full rect drop; do printf '  %s rounds: ' "$c"; tr '\n' ' ' <"$T/$c/o.rounds" 2>/dev/null; echo; done
[ "$fail" = 0 ]
