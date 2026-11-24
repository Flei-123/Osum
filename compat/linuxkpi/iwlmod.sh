#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?usage: iwlmod.sh <output-dir> [shim-dir]}"
SHIM="${2:-compat/linuxkpi/shim}"
DRIVER=iwlwifi
. compat/linuxkpi/flags.sh
. tools/lib/tmpdir.sh
W=$(mktemp -d)
osum_tmp_guard "" "$W"
lkpi_fetch_headers "$DRIVER" "$W/hdr"
lkpi_flags "$SHIM"
lkpi_driver_flags "$DRIVER"
TREE=$(bash compat/linuxkpi/fetch.sh "$DRIVER" "$W/fetch")
mkdir -p "$OUT"
FW_FILE="${IWL_FW_FILE:-$(bash compat/linuxkpi/fetch.sh fw-iwlwifi-8265 "$W/fw")}"
FW_NAME=$(basename "$FW_FILE")
FW_HASH=$(sha256sum "$FW_FILE" | cut -d' ' -f1)
FW_SIZE=$(stat -c %s "$FW_FILE")
mkdir -p "$W/fwinc"
python3 -I - "$W/fwinc/iwl_fwinfo.h" "$FW_NAME" "$FW_HASH" "$FW_SIZE" <<'PY'
import sys
path, name, digest, size = sys.argv[1:5]
cap = (int(size) + 0xFFFFF) & ~0xFFFFF
body = ", ".join("0x" + digest[i:i + 2] for i in range(0, 64, 2))
open(path, "w").write('#define IWL_FW_NAME "%s"\n#define IWL_FW_CAP %d\nstatic const unsigned char iwl_fw_hash[32] = { %s };\n' % (name, cap, body))
PY
shim_objs=(); drv_objs=()
DEBUG_FLAGS=()
PUMP_FLAGS=()
[ "${LKPI_IWL_PUMP:-1}" != 1 ] || PUMP_FLAGS=(-DLKPI_IWL_PUMP)
[ "${LKPI_IWL_DEBUG:-0}" != 1 ] || DEBUG_FLAGS=(-DCONFIG_IWLWIFI_DEBUG=1)
for name in $LKPI_WIFI_MODULE_SOURCES; do
	"$LKPI_CC" "${LKPI_CFLAGS[@]}" -c "$SHIM/src/$name.c" -o "$W/shim_$name.o"
	shim_objs+=("$W/shim_$name.o")
done
if [ "${LKPI_IWL_DEBUG:-0}" = 1 ]; then
	"$LKPI_CC" "${LKPI_CFLAGS[@]}" "${LKPI_DRIVER_FLAGS[@]}" -DCONFIG_IWLWIFI_DEBUG=1 -DLKPI_IWL_DEBUG "${PUMP_FLAGS[@]}" -I"$LKPI_INC" -I"$W/fwinc" -I"$TREE/drivers/net/wireless/intel/iwlwifi" -I"$TREE" \
		-c "$SHIM/driver/iwl_drvmain.c" -o "$W/iwl_drvmain.o"
else
	"$LKPI_CC" "${LKPI_CFLAGS[@]}" "${PUMP_FLAGS[@]}" -I"$W/fwinc" -c "$SHIM/driver/iwl_drvmain.c" -o "$W/iwl_drvmain.o"
fi
drv_objs+=("$W/iwl_drvmain.o")
pids=()
while read -r unit; do
	[ -n "$unit" ] || continue
	obj="$W/drv_${unit//\//_}.o"
	"$LKPI_CC" "${LKPI_CFLAGS[@]}" "${LKPI_DRIVER_FLAGS[@]}" "${DEBUG_FLAGS[@]}" -I"$LKPI_INC" -I"$TREE/$(dirname "$unit")" -I"$TREE" \
		-c "$TREE/$unit" -o "$obj" &
	pids+=($!)
	drv_objs+=("$obj")
	if [ "${#pids[@]}" -ge "${LKPI_JOBS:-4}" ]; then wait "${pids[0]}"; pids=("${pids[@]:1}"); fi
done < "compat/linuxkpi/units/$DRIVER.txt"
for p in "${pids[@]}"; do wait "$p"; done
ld -r -o "$OUT/linuxkpiwifi.o" "${shim_objs[@]}"
ld -r -o "$OUT/iwlwifi.o" "${drv_objs[@]}"
strip --strip-debug "$OUT/linuxkpiwifi.o" "$OUT/iwlwifi.o"
ls -l "$OUT"/linuxkpiwifi.o "$OUT"/iwlwifi.o
size "$OUT"/linuxkpiwifi.o "$OUT"/iwlwifi.o
python3 -I compat/linuxkpi/closure.py --header "$SHIM/include/osum/osum_if.h" --ksym kernel/lib/ksym.fi \
	"$OUT/linuxkpiwifi.o" "$OUT/iwlwifi.o"
python3 -I tools/module/mkomod.py bauen "$OUT/linuxkpiwifi.o" "$OUT/linuxkpiwifi.omod" --name linuxkpiwifi --abi 1
python3 -I tools/module/mkomod.py bauen "$OUT/iwlwifi.o" "$OUT/iwlwifi.omod" --name iwlwifi --abi 1
printf '%s:%s\n' "$FW_NAME" "$FW_HASH" > "$OUT/iwlwifi.fw"
