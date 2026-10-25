#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
[ -x vendor/firn/bin/firnc ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
vendor/firn/bin/firnc --profile=app tools/svg/bake.fi -o "$T/bake" >/dev/null
python3 -I tools/svg/mkapps.py "$(pwd)" "$T/bake" "$@"
