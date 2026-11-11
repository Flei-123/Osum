#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/firnenv.sh
CC=$FIRNC
P=${1:?programm}
OUT=${2:-/tmp/betrieb-wirt}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/lock.sh" && osum_sperre "$OUT"   # A-024
mkdir -p "$OUT"
as --64 -o "$OUT/crt-wirt.o" tools/operation/crt-wirt.s || exit 1
"$CC" "kernel/user/$P.fi" -o "$OUT/$P.o" || exit 1
ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
   -o "$OUT/$P" "$OUT/crt-wirt.o" "$OUT/$P.o" || exit 1
echo "$OUT/$P"
