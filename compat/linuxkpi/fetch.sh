#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
DRIVER="${1:?usage: fetch.sh <driver> <empty-output-dir>}"
OUT="${2:?usage: fetch.sh <driver> <empty-output-dir>}"
TSV=compat/linuxkpi/sources.tsv
row=$(awk -F'\t' -v d="$DRIVER" 'NR>1 && $1==d' "$TSV")
[ -n "$row" ] || { echo "fetch: unknown driver $DRIVER" >&2; exit 2; }
IFS=$'\t' read -r _ version url tsha file fsha spdx _ _ <<<"$row"
case "$OUT" in "$(pwd)"/*) echo "fetch: output must be outside the repository" >&2; exit 2;; esac
mkdir -p "$OUT"
[ -z "$(ls -A "$OUT")" ] || { echo "fetch: output directory not empty" >&2; exit 2; }
TARBALL="$OUT/linux-$version.tar.xz"
if [ -n "${LINUXKPI_TARBALL:-}" ]; then cp "$LINUXKPI_TARBALL" "$TARBALL"; else curl -fsSL -o "$TARBALL" "$url"; fi
echo "$tsha  $TARBALL" | sha256sum -c --quiet - || { rm -f "$TARBALL"; echo "fetch: tarball sha256 mismatch" >&2; exit 3; }
mkdir -p "$OUT/src"
tar -xJf "$TARBALL" -C "$OUT/src" --strip-components=1 "linux-$version/$file" "linux-$version/LICENSES/preferred/GPL-2.0"
echo "$fsha  $OUT/src/$file" | sha256sum -c --quiet - || { echo "fetch: file sha256 mismatch" >&2; exit 3; }
echo "$OUT/src/$file"
