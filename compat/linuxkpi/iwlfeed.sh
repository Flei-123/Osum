#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${1:?usage: iwlfeed.sh <feed-dir> <catalog-seed-file> [firmware-file]}"
SEED="${2:?catalog seed file missing}"
. tools/lib/tmpdir.sh
W=$(mktemp -d)
osum_tmp_guard "" "$W"
FW_FILE="${3:-$(bash compat/linuxkpi/fetch.sh fw-iwlwifi-8265 "$W/fw")}"
IWL_FW_FILE="$FW_FILE" bash compat/linuxkpi/iwlmod.sh "$W/m" > "$W/mod.txt"
FW_LINE=$(cat "$W/m/iwlwifi.fw")
bash compat/linuxkpi/wifipack.sh "$W/m/linuxkpiwifi.omod" "$W/m/iwlwifi.omod" "$W/pk" lkpi-iwlwifi "pci 8086:24fd" "$FW_LINE" > /dev/null
python3 -I tools/drvfeed/mkfeed.py "$OUT" --seed "$SEED" --pkg "$W/pk/lkpi-iwlwifi" \
	--title "lkpi-iwlwifi=Intel Wireless 8265 (Linux iwlwifi via LinuxKPI)" --fw "${FW_LINE%%:*}=$FW_FILE"
