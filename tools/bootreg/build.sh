#!/bin/bash
set -eu
usage() { echo "usage: build.sh <outdir> | build.sh <outdir> proof <name> <marker> [fail]" >&2; exit 2; }
[ $# -ge 1 ] || usage
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OUT=$(mkdir -p "$1" && cd "$1" && pwd)
CC=${BOOTREG_CC:-x86_64-w64-mingw32-gcc}
FLAGS=(-std=gnu11 -O2 -Wall -Wextra -Werror -ffreestanding -fno-builtin -fno-stack-protector
    -fno-tree-loop-distribute-patterns -fno-asynchronous-unwind-tables -fno-pic -mno-red-zone
    -nostdlib -Wl,--subsystem,10 -Wl,-e,efi_main -Wl,--gc-sections)
if [ $# -eq 1 ]; then
    exec "$CC" "${FLAGS[@]}" -o "$OUT/bootreg.efi" \
        "$HERE/main.c" "$HERE/config.c" "$HERE/hits.c" "$HERE/bootvars.c" "$HERE/util.c"
fi
[ "$2" = proof ] && [ $# -ge 4 ] || usage
EXTRA=(-DPROOF_MARKER="\"$4\"")
[ "${5:-}" = fail ] && EXTRA+=(-DPROOF_RETURN_ERROR)
exec "$CC" "${FLAGS[@]}" "${EXTRA[@]}" -o "$OUT/$3.efi" "$HERE/proof.c" "$HERE/util.c"
