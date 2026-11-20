#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${1:?workdir from prep-wine.sh}
OUT=${2:?outdir}
mkdir -p "$OUT"
: "${KERNEL:?wide kernel image}"
python3 -I tools/linuxapps/prof/hmpsample.py "$OUT/mon.sock" "$OUT/samples.txt" "${TMO:-1200}" > /dev/null 2>&1 &
SAMPLER=$!
trap 'kill $SAMPLER 2>/dev/null' EXIT
SPEC=${SPEC:-$WD/run/spec.txt} BLOCKS=${BLOCKS:-2400000} INODES=${INODES:-20000} TMO=${TMO:-1200} DONE=FX-END \
    bash tools/linuxapps/run.sh "$WD" tools/linuxapps/guest-wine-warm.sh "$OUT" > "$OUT.log" 2>&1
kill $SAMPLER 2>/dev/null
grep -a "WINE-WARM" "$OUT/ser.clean"
python3 -I tools/linuxapps/prof/hmpreport.py "$OUT/samples.txt" "$KERNEL.elf" "${TOP:-25}" 0
