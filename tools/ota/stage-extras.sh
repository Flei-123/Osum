#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
IMG=${1:?usage: stage-extras.sh <image-dir> <extra-dir>}
EXTRA=${2:?usage: stage-extras.sh <image-dir> <extra-dir>}
LIST=${OVERLAY_ASSETS:-tools/ota/overlay-assets.txt}
REGISTRY="$IMG/appreg/usr/share/appreg"

while read -r dest src; do
    [ -n "$dest" ] || continue
    [ -s "$src" ] || { echo "stage-extras: missing source $src" >&2; exit 1; }
    mkdir -p "$EXTRA/$(dirname "${dest#/}")"
    cp "$src" "$EXTRA/${dest#/}"
    echo "stage-extras: asset $dest"
done < "$LIST"

[ -d "$REGISTRY" ] || { echo "stage-extras: missing app registry $REGISTRY" >&2; exit 1; }
mkdir -p "$EXTRA/usr/share"
cp -a "$REGISTRY" "$EXTRA/usr/share/"
echo "stage-extras: appreg $(find "$REGISTRY" -type f | wc -l) files"
