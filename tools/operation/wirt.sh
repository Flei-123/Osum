#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/operation/wirt.sh -- ein Programm aus kernel/user/ fuer den WIRT
# bauen. Siehe crt-wirt.s: derselbe Quelltext, dieselbe Bibliothek,
# derselbe Uebersetzer -- nur der Lader ist Linux statt Osum.
#
#   bash tools/operation/wirt.sh <name> [ausgabe]
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
CC=${FIRNC:-vendor/firn/bin/firnc}
P=${1:?programm}
OUT=${2:-/tmp/betrieb-wirt}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/sperre.sh" && osum_sperre "$OUT"   # A-024
mkdir -p "$OUT"
as --64 -o "$OUT/crt-wirt.o" tools/operation/crt-wirt.s || exit 1
"$CC" "kernel/user/$P.fi" -o "$OUT/$P.o" || exit 1
ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
   -o "$OUT/$P" "$OUT/crt-wirt.o" "$OUT/$P.o" || exit 1
echo "$OUT/$P"
