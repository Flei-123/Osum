#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/odbc/qemu.sh -- run an OrientOS image in qemu with ODB wired to a unix socket (docs/ODB.md section 1).
#
#   [QEMU_DRIVE=ide|ahci|virtio] tools/odbc/qemu.sh start <image> <dir> [smp] [mem_mb]   boot headless (KVM if possible); <dir>/odb.sock, com1.log, qemu.pid
#   tools/odbc/qemu.sh stop <dir>                           kill that qemu (by pidfile only) and remove the socket
#   tools/odbc/qemu.sh port <dir>                           print the odbc port spec: unix:<dir>/odb.sock
#   tools/odbc/qemu.sh status <dir>
#
# COM1 (first -serial) = kernel console log, COM2 (second -serial) = odbd on the chardev socket.
# The socket is a server (wait=off): odbc connects to it at any time, also across guest reboots.
# Use a private <dir> (mktemp -d); the image is NOT copied: pass a copy if the guest writes to it.
set -uo pipefail
cmd=${1:-help}; shift || true
case $cmd in
  start)
    img=${1:?image}; d=${2:?dir}; smp=${3:-2}; mem=${4:-1536}
    mkdir -p "$d"; rm -f "$d/odb.sock" "$d/qemu.pid"
    # QEMU_DRIVE: ide (default; SeaBIOS reads the Limine files by port I/O: ~15 s for a 70 MB root.img) | ahci (DMA like real
    # SATA, the loader needs ~1 s) | virtio. tools/bench/measure.sh uses ahci.
    case ${QEMU_DRIVE:-ide} in
        ahci) drv=(-device ich9-ahci,id=ahci0 -drive if=none,id=hd0,file="$img",format=raw -device ide-hd,drive=hd0,bus=ahci0.0) ;;
        virtio) drv=(-drive file="$img",format=raw,if=virtio) ;;
        *) drv=(-drive file="$img",format=raw,if=ide) ;;
    esac
    kvm=""; [ -w /dev/kvm ] && kvm="-enable-kvm -cpu host"
    # QEMU_EXTRA: extra qemu arguments (word-split), e.g. a -monitor socket or -D logfile (tools/bench/measure.sh --portio)
    # shellcheck disable=SC2086
    qemu-system-x86_64 $kvm ${QEMU_EXTRA:-} -smp "$smp" -m "$mem" -display none -no-reboot \
        "${drv[@]}" \
        -serial file:"$d/com1.log" \
        -chardev socket,id=odb,path="$d/odb.sock",server=on,wait=off -serial chardev:odb \
        -netdev user,id=n0 -device e1000,netdev=n0 \
        -pidfile "$d/qemu.pid" -daemonize
    for _ in $(seq 1 50); do [ -S "$d/odb.sock" ] && break; sleep 0.1; done
    [ -S "$d/odb.sock" ] && echo "OK: qemu up pid $(cat "$d/qemu.pid") port unix:$d/odb.sock" || { echo "FAIL: no socket"; exit 1; } ;;
  stop)
    d=${1:?dir}
    if [ -f "$d/qemu.pid" ]; then kill "$(cat "$d/qemu.pid")" 2>/dev/null; rm -f "$d/qemu.pid"; fi
    rm -f "$d/odb.sock"; echo "OK: stopped" ;;
  port) echo "unix:${1:?dir}/odb.sock" ;;
  status)
    d=${1:?dir}
    if [ -f "$d/qemu.pid" ] && kill -0 "$(cat "$d/qemu.pid")" 2>/dev/null; then echo "running pid $(cat "$d/qemu.pid")"; else echo "stopped"; fi ;;
  *) sed -n 2,12p "$0" ;;
esac
