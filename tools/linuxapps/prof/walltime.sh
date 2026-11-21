#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../../.."
KERNEL=${1:?kernel image}
OUT=${2:?outdir}
RUNS=${3:-6}
DRIVE_KIND=${4:-ahci}
export BLOCKS=1000000 TMO=${TMO:-900} FX_RUNS=$RUNS DRIVE=$DRIVE_KIND
export "KARGS=osum vfs nokbd nosched noproc nofs gfx nic nip=10.0.2.15/24 ngw=10.0.2.2 ${KARGS_EXTRA:-}" "QEMU_EXTRA=-netdev user,id=n0 -device e1000,netdev=n0"
export KERNEL
SAMPLER=0
if [ -z "${NOSAMPLE:-}" ]; then
    python3 tools/linuxapps/prof/${SAMPLE_SCRIPT:-hmpsample.py} "$OUT/mon.sock" "$OUT/samples.txt" "$TMO" > /dev/null 2>&1 &
    SAMPLER=$!
fi
bash tools/linuxapps/run.sh "${FXWD:-/root/abbilder/fxscudo/wd}" "${FXGUEST:-tools/linuxapps/guest-fx12-wall.sh}" "$OUT"
[ "$SAMPLER" != 0 ] && kill "$SAMPLER" 2>/dev/null
grep -a "FX11 run .* rc=" "$OUT/ser.txt"
