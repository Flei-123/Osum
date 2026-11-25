#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../../../.."
KERNEL=${1:?kernel image}
OUT=${2:?output directory}
export KERNEL
export BLOCKS=${BLOCKS:-1000000} TMO=${TMO:-500} DRIVE=${DRIVE:-ahci} DONE=${DONE:-FX-END}
export "KARGS=osum vfs nokbd nosched noproc nofs gfx nic nip=10.0.2.15/24 ngw=10.0.2.2 ${KARGS_EXTRA:-}"
export "QEMU_EXTRA=-netdev user,id=n0 -device e1000,netdev=n0 ${QEMU_MORE:-}"
exec bash tools/linuxapps/run.sh "${FXWD:?FXWD workdir}" "${FXGUEST:-tools/linuxapps/prof/fx19/guest.sh}" "$OUT"
