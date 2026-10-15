#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/xhciisoq/run.sh -- gate for xHCI isochronous OUT transfers in QEMU (r813).
#
#   bash tools/xhciisoq/run.sh
#
# MEASURES (QEMU `-device qemu-xhci -device usb-audio`, wav audio backend):
#   * kernel word `isoctest`: the audio control interface is bound to the isoc test driver
#   * Configure Endpoint accepts the isochronous OUT endpoint (alt 1, 192 byte packets)
#   * 200 TDs (one Isoch TRB each) are queued; 200 transfer events come back, 38400 bytes moved
#   * the 1 kHz square wave the driver wrote arrives in QEMU's audio backend (wav file)
# CONTROL RUNS:
#   * without the word the same device is NOT bound (no isoc line)
#   * without a usb-audio device there is no isoc line
# NOT MEASURED: isochronous IN (QEMU 7.2 usb-audio has no capture path), super speed bursts,
#   real timing (TCG/KVM frame pacing is not a hardware clock). See docs/XHCIISO.md.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null || { echo "XHCIISOQ: skipped, no qemu"; exit 0; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 || { tail "$T/k.txt"; exit 1; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm

run() { # name extra-kernel-words extra-qemu-args...
    local name=$1 words=$2; shift 2
    timeout 60 qemu-system-x86_64 -accel $ACC -kernel "$T/k.img" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 usb usbpoll $words" \
        -serial "file:$T/$name.txt" -display none -no-reboot \
        -device qemu-xhci,id=x0 "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$name.txt" > "$T/$name.klar"
}

run iso "isoctest" -audiodev "wav,id=a0,path=$T/out.wav" -device usb-audio,audiodev=a0
M="$T/iso.klar"
chk() { grep -aq -- "$2" "$M" && ok "$1" || { bad "$1 (missing: $2)"; }; }
chk "audio control interface bound to isoc driver" 'driver=isoc'
chk "streaming alt 1, 192 byte packets"            'usb: isoc alt=1 mps=192'
chk "200 TDs queued"                               'queued=200 '
chk "200 transfer events back"                     'events=200 '
chk "38400 bytes moved (200 x 192)"                'bytes=38400 '
grep -aq ' missed=0 err=0$' "$M" && ok "no missed service, no bad completion code" || bad "missed service / bad completion codes (see line below)"
grep -aqE ' under=[0-2] ' "$M" && ok "ring underrun events <= 2 (one follows the last TD)" || bad "stream ran dry too often (under=)"
grep -a 'usb: isoc' "$M" | head -3

# the wav file: a 1 kHz square wave, 16 bit stereo 48 kHz
if [ -s "$T/out.wav" ]; then
    python3 -I - "$T/out.wav" > "$T/wav.txt" 2>&1 <<'PY'
import sys, struct
d = open(sys.argv[1], 'rb').read()
i = d.find(b'data')
pcm = d[i + 8:] if i >= 0 else b''
n = len(pcm) // 4
hi = lo = flips = 0
prev = 0
for k in range(n):
    v = struct.unpack_from('<h', pcm, k * 4)[0]
    s = 1 if v > 5000 else (-1 if v < -5000 else 0)
    if s == 1: hi += 1
    if s == -1: lo += 1
    if s != 0:
        if prev != 0 and s != prev: flips += 1
        prev = s
print("frames", n, "hi", hi, "lo", lo, "flips", flips)
PY
    read -r _ frames _ hi _ lo _ flips < <(grep '^frames' "$T/wav.txt")
    [ "${hi:-0}" -ge 2000 ] && [ "${lo:-0}" -ge 2000 ] && ok "wav: loud high and low samples (hi=$hi lo=$lo)" || bad "wav: no square wave ($(cat "$T/wav.txt" | head -2))"
    [ "${flips:-0}" -ge 100 ] && ok "wav: $flips polarity flips (1 kHz tone)" || bad "wav: only ${flips:-0} flips"
else
    bad "wav: no audio file written"
fi

# control: no word -> not bound
run noword "" -audiodev "wav,id=a0,path=$T/o2.wav" -device usb-audio,audiodev=a0
N="$T/noword.klar"
grep -aq 'driver=isoc' "$N" && bad "noword: bound without the word" || ok "noword: audio device not bound"
grep -aq 'usb: isoc alt' "$N" && bad "noword: isoc line without the word" || ok "noword: no isoc line"

# control: no device
run nodev "isoctest"
D="$T/nodev.klar"
grep -aq 'usb: isoc alt' "$D" && bad "nodev: isoc line without device" || ok "nodev: no isoc line without device"

echo "XHCIISOQ: $pass ok, $fail fail"
if [ "$fail" -gt 0 ]; then
    grep -a "usb" "$M" | head -20
    exit 1
fi
exit 0
