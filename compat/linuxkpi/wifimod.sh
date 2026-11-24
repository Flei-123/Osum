#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?usage: wifimod.sh <output-dir> [shim-dir]}"
SHIM="${2:-compat/linuxkpi/shim}"
. compat/linuxkpi/flags.sh
. tools/lib/tmpdir.sh
W=$(mktemp -d)
osum_tmp_guard "" "$W"
lkpi_fetch_headers wifi "$W/hdr"
lkpi_flags "$SHIM"
mkdir -p "$OUT"
shim_objs=(); drv_objs=()
for name in $LKPI_WIFI_MODULE_SOURCES; do
	"$LKPI_CC" "${LKPI_CFLAGS[@]}" -c "$SHIM/src/$name.c" -o "$W/$name.o"
	shim_objs+=("$W/$name.o")
done
for name in $LKPI_WIFI_DRIVER_SOURCES; do
	"$LKPI_CC" "${LKPI_CFLAGS[@]}" -c "$SHIM/driver/$name.c" -o "$W/$name.o"
	drv_objs+=("$W/$name.o")
done
ld -r -o "$OUT/linuxkpiwifi.o" "${shim_objs[@]}"
ld -r -o "$OUT/wififake_drv.o" "${drv_objs[@]}"
python3 -I compat/linuxkpi/closure.py --header "$SHIM/include/osum/osum_if.h" --ksym kernel/lib/ksym.fi \
	"$OUT/linuxkpiwifi.o" "$OUT/wififake_drv.o"
python3 -I tools/module/mkomod.py bauen "$OUT/linuxkpiwifi.o" "$OUT/linuxkpiwifi.omod" --name linuxkpiwifi --abi 1
python3 -I tools/module/mkomod.py bauen "$OUT/wififake_drv.o" "$OUT/wififake_drv.omod" --name wififake --abi 1
