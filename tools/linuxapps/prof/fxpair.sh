#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../../.."
OUT=${1:?output directory}
shift
KERNELS=("$@")
[ ${#KERNELS[@]} -gt 0 ] || { echo "usage: fxpair.sh <out> <kernel.img>..." >&2; exit 2; }
RUNS=${FX_RUNS:-4}
LINUX_SMP=${LINUX_SMP:-1}
GUEST=${FXGUEST:-/root/abbilder/svl/lin/gfx-https.sh}
mkdir -p "$OUT"
PIDS=()
if [ -z "${NOLINUX:-}" ]; then
    FX_RUNS=$RUNS TMO=${TMO:-400} bash /root/abbilder/svl/lin/lin.sh https "$LINUX_SMP" "$OUT/linux" > "$OUT/linux.log" 2>&1 &
    PIDS+=($!)
fi
index=0
for kernel in "${KERNELS[@]}"; do
    index=$((index + 1))
    snapshot=${DRIVE_SNAP-1}
    if [[ $kernel == *:nosnap ]]; then
        kernel=${kernel%:nosnap}
        snapshot=
    fi
    DRIVE_SNAP=$snapshot FXWD=${FXWD:-/root/abbilder/wwds/wd} NOSAMPLE=1 SMP=${OSUM_SMP:-1} KERNEL=$kernel \
        FXGUEST=$GUEST TMO=${TMO:-400} DONE=FX-END \
        /root/jarvis/bin/heavy bash tools/linuxapps/prof/walltime.sh "$kernel" "$OUT/osum$index" "$RUNS" ahci > "$OUT/osum$index.log" 2>&1 &
    PIDS+=($!)
done
wait "${PIDS[@]}"
python3 - "$OUT" "${#KERNELS[@]}" <<'EOF'
import re, statistics, sys

out, count = sys.argv[1], int(sys.argv[2])
names = ["linux"] + ["osum%d" % i for i in range(1, count + 1)]
for name in names:
    try:
        text = open("%s/%s/ser.txt" % (out, name), errors="replace").read()
    except OSError:
        continue
    marks = {}
    for run, kind, t in re.findall(r"FX11 run (\d+) (begin|png|rc)\S* t=([0-9.]+)", text):
        marks[(int(run), kind)] = float(t)
    first_png = [marks[(r, "png")] - marks[(r, "begin")] for r in range(2, 20) if (r, "png") in marks and (r, "begin") in marks]
    to_exit = [marks[(r, "rc")] - marks[(r, "png")] for r in range(2, 20) if (r, "rc") in marks and (r, "png") in marks]
    if first_png:
        print("%-7s begin->png %s  median %.2f | png->rc median %.2f" % (
            name, " ".join("%.2f" % v for v in first_png), statistics.median(first_png),
            statistics.median(to_exit) if to_exit else 0.0))
EOF
