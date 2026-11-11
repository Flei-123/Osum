#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
. tools/lib/firnenv.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
"$FIRNC" --profile=app tools/svg/bake.fi -o "$T/bake" >/dev/null
python3 -I tools/svg/mkapps.py "$(pwd)" "$T/bake" "$@"
