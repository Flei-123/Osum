#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
img=$1; out=$2; settle=${3:-60}; cpu=${NMI_CPU:-Skylake-Client,pmu=on}; smp=${NMI_SMP:-4}
here=$(cd "$(dirname "$0")" && pwd)
W=$(mktemp -d); trap 'kill $qpid 2>/dev/null; rm -rf "$W"' EXIT
code=/usr/share/OVMF/OVMF_CODE_4M.fd; vars=/usr/share/OVMF/OVMF_VARS_4M.fd
cp "$img" "$W/d.img"; cp "$vars" "$W/vars.fd"
qemu-system-x86_64 -machine q35 -accel kvm -cpu "$cpu" -smp "$smp" -m 2048 \
    -drive if=pflash,format=raw,readonly=on,file="$code" -drive if=pflash,format=raw,file="$W/vars.fd" \
    -drive file="$W/d.img",format=raw,if=none,id=d0 -device ahci,id=ah -device ide-hd,drive=d0,bus=ah.0 \
    -device qemu-xhci -device usb-kbd -device usb-tablet -vga std -nic none \
    -global ICH9-LPC.noreboot=false -watchdog-action reset \
    -serial "file:$W/serial.txt" -display none -qmp "unix:$W/qmp,server,nowait" </dev/null >/dev/null 2>&1 &
qpid=$!
timeout $((settle + 400)) python3 "$here/desktop.py" "$W/qmp" "$W/serial.txt" "$settle" > "$out.steps" 2>&1
kill $qpid 2>/dev/null; wait $qpid 2>/dev/null
tr -cd '\11\12\15\40-\176' < "$W/serial.txt" > "$out"
