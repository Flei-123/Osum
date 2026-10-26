#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
OVMF_CODE=/usr/share/OVMF/OVMF_CODE_4M.fd
OVMF_VARS=/usr/share/OVMF/OVMF_VARS_4M.fd
[ -f "$OVMF_CODE" ] && [ -f "$OVMF_VARS" ] || { echo "GOPFB: OVMF firmware missing"; exit 1; }
[ -n "${STICK_IMG:-}" ] && [ -f "$STICK_IMG" ] || { echo "GOPFB: set STICK_IMG to a built stick image"; exit 1; }
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
SECS=${GOPFB_SECS:-50}
MINLIT=${GOPFB_MINLIT:-600}

probe() {
    local name=$1; shift
    local sock="$D/$name.sock" ser="$D/$name.txt" ppm="$D/$name.ppm"
    cp "$STICK_IMG" "$D/$name.img"
    cp "$OVMF_VARS" "$D/$name.vars"
    timeout $((SECS+60)) qemu-system-x86_64 "${KVM[@]}" -machine q35 -m 2048 -smp 2 "$@" \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE" \
        -drive "if=pflash,format=raw,unit=1,file=$D/$name.vars" \
        -drive "file=$D/$name.img,format=raw,if=none,id=stick" -device qemu-xhci -device usb-storage,drive=stick \
        -serial "file:$ser" -display none -no-reboot -monitor "unix:$sock,server,nowait" &
    local pid=$!
    sleep "$SECS"
    python3 -I tools/gfx/screenshot.py "$sock" "$ppm" 20 > "$D/$name.shot" 2>&1
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    rm -f "$D/$name.img" "$D/$name.vars"
    local fbline lit
    fbline=$(tr -cd '\11\12\15\40-\176' < "$ser" | grep -a '^fb: [0-9]*x[0-9]*x32' | head -1)
    case "$fbline" in
        *"src=mb"*) ok "$name: kernel took the loader framebuffer ($(echo "$fbline" | cut -c1-48))" ;;
        *) bad "$name: no loader framebuffer line (${fbline:-none})" ;;
    esac
    if [ ! -s "$ppm" ]; then bad "$name: no screenshot"; return; fi
    lit=$(python3 -I tools/gopfb/litpct.py "$ppm")
    set -- $lit
    if [ "$3" -ge "$MINLIT" ]; then ok "$name: screen is not black (${1}x${2}, $3 permille lit)"
    else bad "$name: screen black (${1}x${2}, $3 permille lit)"; fi
}

echo "== OVMF + non-virtio display devices =="
probe std -vga std
probe bochs -vga none -device bochs-display
probe ramfb -vga none -device ramfb
probe qxl -vga qxl
echo "GOPFB: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
