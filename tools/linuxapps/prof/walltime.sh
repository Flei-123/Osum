#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../../.."
KERNEL=${1:?kernel image}
OUT=${2:?outdir}
RUNS=${3:-3}
DRIVE_KIND=${4:-ahci}
export BLOCKS=1000000 TMO=${TMO:-900} FX_RUNS=$RUNS DRIVE=$DRIVE_KIND
export "KARGS=osum vfs nokbd nosched noproc nofs gfx nic nip=10.0.2.15/24 ngw=10.0.2.2" "QEMU_EXTRA=-netdev user,id=n0 -device e1000,netdev=n0"
export KERNEL
python3 tools/linuxapps/prof/hmpsample.py "$OUT/mon.sock" "$OUT/samples.txt" "$TMO" > /dev/null 2>&1 &
SAMPLER=$!
bash tools/linuxapps/run.sh "${FXWD:-/root/abbilder/fxscudo/wd}" tools/linuxapps/guest-fx12-wall.sh "$OUT"
kill "$SAMPLER" 2>/dev/null
grep -a "FX11 run .* rc=" "$OUT/ser.txt"
