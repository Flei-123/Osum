#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
main=$1
dir=${main%.fi}
mods=$(for f in "$dir"/*.fi; do basename "$f" .fi; done | paste -sd'|')
cat "$main" "$dir"/*.fi | LC_ALL=C sed -E "s/(^|[^A-Za-z0-9_.])($mods)\.([A-Za-z_])/\1\3/g"
