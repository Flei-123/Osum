#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
SHIM_OMOD="${1:?usage: wifipack.sh <linuxkpiwifi.omod> <driver.omod> <outdir> [name] [match] [fw name:sha256]}"
DRV_OMOD="$2"; OUT="$3"
NAME="${4:-lkpi-wififake}"
MATCH="${5:-pci 1234:11e8}"
FW="${6:-}"
mkdir -p "$OUT"
fw_args=()
[ -z "$FW" ] || fw_args=(--fw "$FW")
python3 -I tools/drvstore/mkpkg.py build "$OUT" --name "$NAME" --module "$DRV_OMOD" --requires "$SHIM_OMOD" \
	--tier compat --rank 5 --rights pci-cfg,mmio,irq,dma,fw --match "$MATCH" "${fw_args[@]}"
