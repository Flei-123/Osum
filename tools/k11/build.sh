#!/usr/bin/env bash
# tools/k11/build.sh -- ein einzelnes Programm dieser Runde uebersetzen
# und binden. Nur zum Iterieren waehrend der Arbeit; die Abnahme baut in
# tools/k11/run.sh alles noch einmal aus BEIDEN Uebersetzern.
#
#   bash tools/k11/build.sh edit find sed ...
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
CC=${FIRNC:-vendor/firn/bin/firnc}
OUT=${OUT:-/tmp/k11build}
mkdir -p "$OUT"
[ -f "$OUT/crt.o" ] || as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1
rc=0
for p in "$@"; do
    if ! "$CC" "kernel/user/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1; then
        echo "== $p: der Uebersetzer sagt nein"
        head -25 "$OUT/$p.err"
        rc=1
        continue
    fi
    if ! ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start \
            -o "$OUT/$p.elf" "$OUT/crt.o" "$OUT/$p.o" 2> "$OUT/$p.lderr"; then
        echo "== $p: der Binder sagt nein"
        head -12 "$OUT/$p.lderr"
        rc=1
        continue
    fi
    strip --strip-all "$OUT/$p.elf"
    printf '   %-10s %7d Oktette\n' "$p" "$(stat -c%s "$OUT/$p.elf")"
done
exit $rc
