#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
DRIVER="${1:?usage: treeprobe.sh <driver> <report.json>}"
JSON="${2:?usage: treeprobe.sh <driver> <report.json>}"
SHIM="${LKPI_SHIM:-compat/linuxkpi/shim}"
. compat/linuxkpi/flags.sh
lkpi_flags "$SHIM"
lkpi_driver_flags "$DRIVER"
if [ -z "${LINUXKPI_TARBALL:-}" ]; then
	cached="${LINUXKPI_CACHE:-/root/lkpi-src/dl612}/linux-6.12.101.tar.xz"
	[ -f "$cached" ] && export LINUXKPI_TARBALL="$cached"
fi
. tools/lib/tmpdir.sh
W=$(mktemp -d)
osum_tmp_guard "" "$W"
TREE=$(bash compat/linuxkpi/fetch.sh "$DRIVER" "$W/fetch")
lkpi_driver_headers "$DRIVER"
for hdr in $LKPI_DRIVER_HEADERS; do
	path=$(bash compat/linuxkpi/fetch.sh "$hdr" "$W/$hdr")
	rel=${path#"$W/$hdr/src/include/"}; rel=${rel#uapi/}
	mkdir -p "$W/inc/$(dirname "$rel")"; cp "$path" "$W/inc/$rel"
done
shim_args=()
for name in $LKPI_WIFI_MODULE_SOURCES; do
	"$LKPI_CC" "${LKPI_CFLAGS[@]}" -c "$SHIM/src/$name.c" -o "$W/$name.o"
	shim_args+=(--shim-obj "$W/$name.o")
done
flag_args=()
for f in "${LKPI_CFLAGS[@]}" "${LKPI_DRIVER_FLAGS[@]}" "-I$W/inc"; do flag_args+=("--flag=$f"); done
python3 -I compat/linuxkpi/treeprobe.py --tree "$TREE" --units "compat/linuxkpi/units/$DRIVER.txt" --cc "$LKPI_CC" \
	--jobs "${LKPI_JOBS:-4}" --json "$JSON" "${flag_args[@]}" "${shim_args[@]}"
