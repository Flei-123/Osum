#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
SHIM_OMOD="${1:?usage: wifipack.sh <linuxkpiwifi.omod> <wififake_drv.omod> <outdir>}"
DRV_OMOD="$2"; OUT="$3"
mkdir -p "$OUT"
python3 -I tools/drvstore/mkpkg.py build "$OUT" --name lkpi-wififake --module "$DRV_OMOD" --requires "$SHIM_OMOD" \
	--tier compat --rank 5 --rights pci-cfg,mmio,irq,dma,fw --match "pci 1234:11e8"
