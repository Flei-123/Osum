#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
NAME="${1:?usage: pack.sh <driver> <linuxkpi.omod> <driver.omod> <outdir> [firmware-file...]}"
KPI="$2"; DRV="$3"; OUT="$4"; shift 4
TSV=compat/linuxkpi/sources.tsv
row=$(awk -F'\t' -v d="$NAME" 'NR>1 && $1==d' "$TSV")
[ -n "$row" ] || { echo "pack: unknown driver $NAME" >&2; exit 2; }
IFS=$'\t' read -r _ version url tsha file fsha spdx fwlic _ <<<"$row"
mkdir -p "$OUT"
args=(--name "lkpi-$NAME" --module "$DRV" --tier compat --rank 5 --rights pci-cfg,mmio,irq,dma,fw)
while IFS= read -r m; do args+=(--match "$m"); done < "compat/linuxkpi/match-$NAME.txt"
fwargs=()
for f in "$@"; do args+=(--fw "$(basename "$f"):$(sha256sum "$f" | cut -d' ' -f1)"); fwargs+=("$f"); done
pkg=$(python3 -I tools/drvstore/mkpkg.py build "$OUT" "${args[@]}")
cp "$KPI" "$pkg/linuxkpi.omod"
for f in "${fwargs[@]}"; do cp "$f" "$pkg/"; done
{
  echo "driver=$NAME"
  echo "linux_version=$version"
  echo "source_url=$url"
  echo "tarball_sha256=$tsha"
  echo "file=$file"
  echo "file_sha256=$fsha"
  echo "license=$spdx"
  echo "firmware_license=$fwlic"
} > "$pkg/SOURCES.txt"
echo "$pkg"
