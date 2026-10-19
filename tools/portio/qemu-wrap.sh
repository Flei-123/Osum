#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# PATH wrapper named `qemu-system-x86_64` (tools/portio/run.sh symlinks it): runs the real QEMU with memory-region tracing.
# PIO_LOG=<file> receives the trace (every port/MMIO read+write the guest does), each line stamped with seconds since the first line (stamp.py).
real=$(PATH=${PIO_REAL_PATH:?} command -v qemu-system-x86_64)
fifo="$PIO_LOG.fifo"; rm -f "$fifo"; mkfifo "$fifo"
python3 "$(dirname "$(readlink -f "$0")")/stamp.py" "$fifo" > "${PIO_LOG:?}" &
exec "$real" "$@" -trace memory_region_ops_read -trace memory_region_ops_write -D "$fifo"
