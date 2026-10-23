#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/sync/build.sh -- die Programme dieser Runde in ein Verzeichnis,
# damit der Laeufer und ein Mensch, der von Hand nachsieht, denselben
# Befehl benutzen.
#
#   bash tools/sync/build.sh <zielverzeichnis> [stufe] [programm ...]
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/sync/gc.sh   # r278: FIRN_FUNCTION_SECTIONS + ld --gc-sections (OSUM_NO_GC=1 = off)
ROOT=$(pwd)
# FIRNLIB darf von aussen gesetzt sein: die Gegenproben (j) bauen gegen
# eine KOPIE des Bibliotheksbaums, damit kein Test je die echten Quellen
# im Arbeitsbaum anfasst -- ein abgebrochener Lauf soll nichts kaputt
# zuruecklassen.
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
# USRC ebenso (A-028): das Verzeichnis, aus dem die Programme kommen.
# Ein Programm findet `import ulib`, `import kbund` nur neben sich selbst,
# FIRNLIB hilft da nicht. Die Gegenproben (j3, j4) legen deshalb eine
# KOPIE von kernel/user/ an, flicken DORT und bauen mit USRC=<kopie>.
# Der Quelltext im Baum wird von keinem Laeufer mehr angefasst.
USRC="${USRC:-kernel/user}"

OUT=${1:?zielverzeichnis fehlt}
STUFE=${2:-0}
shift 2 || true
PROGS=${*:-}
mkdir -p "$OUT"

if [ "$STUFE" = 0 ]; then CC="$ROOT/vendor/firn/bin/firnc"; else CC="$ROOT/vendor/firn/bin/firnc1"; fi
[ -x "$CC" ] || { echo "Uebersetzer fehlt: $CC" >&2; exit 1; }

as --64 -o "$OUT/crt.o" kernel/user/crt.s || exit 1

# W-BUILD: parallel (OSUM_BUILD_JOBS, default 6; one heavy slot, never nested) + shared object cache
# (tools/kernel/buildcache.sh bc_cc).  The cache is only used for the default sources: a patched USRC copy or a
# FIRNLIB copy (the counter-proof runs) lives outside the tree and would only fill the cache with one-off keys.
. tools/kernel/buildcache.sh
if [ "$USRC" != kernel/user ] || [ "$FIRNLIB" != "$ROOT/lib" ]; then OSUM_PROG_CACHE=0; fi
export BC_STATS="${BC_STATS:-}"
bc_prepare "$CC"
BUILD_JOBS=$(bc_jobs)
build_one() {
    local p=$1 UPROF="" UCRT="$OUT/crt.o"
    grep -qa '^profile app' "$USRC/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    if ! bc_cc "$OUT/$p.o" "$USRC/$p.fi" "$CC" $UPROF $OPTL > "$OUT/$p.err" 2>&1; then
        echo compile > "$OUT/$p.fail"; return
    fi
    if ! ld $GCS -T kernel/user/user.ld --defsym=USER_ENTRY="_F$STUFE.u_start" \
        -o "$OUT/$p.elf" $UCRT "$OUT/$p.o" 2> "$OUT/$p.lderr"; then
        echo link > "$OUT/$p.fail"; return
    fi
    strip --strip-all "$OUT/$p.elf"
}
rc=0
for p in $PROGS; do
    rm -f "$OUT/$p.fail"
    while [ "$(jobs -rp | wc -l)" -ge "$BUILD_JOBS" ]; do wait -n; done
    build_one "$p" &
done
wait
for p in $PROGS; do
    [ -f "$OUT/$p.fail" ] || continue
    if [ "$(cat "$OUT/$p.fail")" = compile ]; then
        echo "FEHLER: firnc$STUFE uebersetzt $p.fi nicht"
        sed 's/^/    /' "$OUT/$p.err" | head -12
    else
        echo "FEHLER: ld scheitert an $p"
        sed 's/^/    /' "$OUT/$p.lderr" | head -8
    fi
    rc=1
done
exit $rc
