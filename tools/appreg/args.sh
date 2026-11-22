#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
out=${1:?usage: args.sh <work-dir>}
rm -rf "$out"
python3 -I tools/appreg/build.py "$PWD" "$out" > "$out.log" 2>&1 || [ -n "${APPS_DIR:-}" ] || { echo "appreg registry failed: $(tail -1 "$out.log")" >&2; exit 1; }
bash tools/appreg/specs.sh "$out"
