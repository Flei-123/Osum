#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?usage: build.sh <output-dir> [driver]}"
DRIVER="${2:-bochs}"
SHIM=compat/linuxkpi/shim
TSV=compat/linuxkpi/sources.tsv
SHIM_SOURCES="heap string printk resource pci drm_core drm_kms drm_vram drm_fbdev shim_main"
CC="${CC:-gcc-12}"
command -v "$CC" >/dev/null 2>&1 || CC=gcc
CFLAGS=(-O2 -ffreestanding -nostdinc -fno-pic -mcmodel=small -mno-red-zone -mgeneral-regs-only
	-fno-stack-protector -fno-asynchronous-unwind-tables -fno-common -fcf-protection=none
	-fno-tree-loop-distribute-patterns -Wall -Wextra -Werror -Wno-unused-parameter "-I$SHIM/include")
DRIVER_FLAGS=()
case "$DRIVER" in
	bochs) DRIVER_FLAGS=(-Wno-pointer-sign) ;;
esac
row=$(awk -F'\t' -v d="$DRIVER" 'NR>1 && $1==d' "$TSV")
[ -n "$row" ] || { echo "build: unknown driver $DRIVER" >&2; exit 2; }
IFS=$'\t' read -r _ version _ <<<"$row"
if [ -z "${LINUXKPI_TARBALL:-}" ]; then
	cached="${LINUXKPI_CACHE:-/root/lkpi-src/dl612}/linux-$version.tar.xz"
	[ -f "$cached" ] && export LINUXKPI_TARBALL="$cached"
fi
. tools/lib/tmpdir.sh
W=$(mktemp -d)
osum_tmp_guard "" "$W"
mkdir -p "$OUT"
SRC=$(bash compat/linuxkpi/fetch.sh "$DRIVER" "$W/fetch")
compile() { "$CC" "${CFLAGS[@]}" "${@:3}" -c "$1" -o "$2"; }
objs=()
for name in $SHIM_SOURCES; do
	compile "$SHIM/src/$name.c" "$W/$name.o"
	objs+=("$W/$name.o")
done
ld -r -o "$OUT/linuxkpi.o" "${objs[@]}"
compile "$SRC" "$W/driver.o" "${DRIVER_FLAGS[@]}"
compile "$SHIM/driver/drvmain.c" "$W/drvmain.o"
ld -r -o "$OUT/${DRIVER}_drv.o" "$W/driver.o" "$W/drvmain.o"
python3 -I compat/linuxkpi/closure.py --header "$SHIM/include/osum/osum_if.h" --ksym kernel/lib/ksym.fi \
	"$OUT/linuxkpi.o" "$OUT/${DRIVER}_drv.o"
python3 -I tools/module/mkomod.py bauen "$OUT/linuxkpi.o" "$OUT/linuxkpi.omod" --name linuxkpi --abi 1
python3 -I tools/module/mkomod.py bauen "$OUT/${DRIVER}_drv.o" "$OUT/${DRIVER}_drv.omod" --name "$DRIVER" --abi 1
