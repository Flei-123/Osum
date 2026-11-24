#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
DRIVER="${1:?usage: fetch.sh <driver> <empty-output-dir>}"
OUT="${2:?usage: fetch.sh <driver> <empty-output-dir>}"
TSV="${LKPI_SOURCES:-compat/linuxkpi/sources.tsv}"
row=$(awk -F'\t' -v d="$DRIVER" 'NR>1 && $1==d' "$TSV")
[ -n "$row" ] || { echo "fetch: unknown driver $DRIVER" >&2; exit 2; }
IFS=$'\t' read -r _ version url tsha file fsha spdx _ _ <<<"$row"
case "$OUT" in "$(pwd)"/*) echo "fetch: output must be outside the repository" >&2; exit 2;; esac
mkdir -p "$OUT"
[ -z "$(ls -A "$OUT")" ] || { echo "fetch: output directory not empty" >&2; exit 2; }
if [ "$tsha" = "-" ]; then
	mkdir -p "$OUT/src"
	target="$OUT/src/$file"
	case "$url" in
		local:*) cp "${LKPI_FW_SOURCE:-${url#local:}}" "$target" ;;
		*) curl -fsSL -o "$target" "$url" ;;
	esac
	echo "$fsha  $target" | sha256sum -c --quiet - || { rm -f "$target"; echo "fetch: file sha256 mismatch" >&2; exit 3; }
	echo "$target"
	exit 0
fi
TARBALL="$OUT/linux-$version.tar.xz"
if [ -n "${LINUXKPI_TARBALL:-}" ]; then cp "$LINUXKPI_TARBALL" "$TARBALL"; else curl -fsSL -o "$TARBALL" "$url"; fi
echo "$tsha  $TARBALL" | sha256sum -c --quiet - || { rm -f "$TARBALL"; echo "fetch: tarball sha256 mismatch" >&2; exit 3; }
mkdir -p "$OUT/src"
IFS=, read -r -a members <<<"${file%/}"
extract=(); for m in "${members[@]}"; do extract+=("linux-$version/$m"); done
tar -xJf "$TARBALL" -C "$OUT/src" --strip-components=1 "${extract[@]}" "linux-$version/LICENSES/preferred/GPL-2.0"
case "$file" in
	*/) got=$(cd "$OUT/src" && find "${file%/}" -type f | LC_ALL=C sort | xargs sha256sum | sha256sum | cut -d' ' -f1)
		[ "$got" = "$fsha" ] || { echo "fetch: tree sha256 mismatch" >&2; exit 3; } ;;
	*,*) got=$(cd "$OUT/src" && printf '%s\n' "${members[@]}" | LC_ALL=C sort | xargs sha256sum | sha256sum | cut -d' ' -f1)
		[ "$got" = "$fsha" ] || { echo "fetch: file set sha256 mismatch" >&2; exit 3; }
		echo "$OUT/src"; exit 0 ;;
	*) echo "$fsha  $OUT/src/$file" | sha256sum -c --quiet - || { echo "fetch: file sha256 mismatch" >&2; exit 3; } ;;
esac
echo "$OUT/src/${file%/}"
