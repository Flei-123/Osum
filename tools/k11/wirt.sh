#!/usr/bin/env bash
# tools/k11/wirt.sh -- dieselben Programme fuer den WIRT bauen.
# Werkbank, keine Abnahme: siehe den Kopf von tools/k11/hostcrt.s.
#   bash tools/k11/wirt.sh find sed diff ...   -> /tmp/k11host/<name>
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
CC=${FIRNC:-vendor/firn/bin/firnc}
OUT=${HOSTOUT:-/tmp/k11host}
mkdir -p "$OUT"
as --64 -o "$OUT/crt.o" tools/k11/hostcrt.s || exit 1
rc=0
for p in "$@"; do
    "$CC" "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1 || {
        echo "== $p"; head -20 "$OUT/$p.err"; rc=1; continue; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
       -o "$OUT/$p" "$OUT/crt.o" "$OUT/$p.o" 2>"$OUT/$p.lderr" || {
        echo "== $p (Binder)"; head -8 "$OUT/$p.lderr"; rc=1; continue; }
done
exit $rc
