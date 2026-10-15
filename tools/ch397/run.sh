#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ch397/run.sh -- host gate for lib/usbnet/ch397.fi (WCH 1A86:539x USB Ethernet, protocol half).
# No QEMU device exists for this chip; the framing is unverified on hardware (see lib header).
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$PWD/lib"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
if ! $FIRNC tools/ch397/test.fi -o "$D/t" 2> "$D/err"; then echo "  FAIL  build"; head -20 "$D/err"; exit 1; fi
"$D/t" | tee "$D/out"
! grep -q '^  FAIL  ' "$D/out" && grep -q 'fail=0' "$D/out"
