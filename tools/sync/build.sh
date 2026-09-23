#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/sync/build.sh -- die Programme dieser Runde in ein Verzeichnis,
# damit der Laeufer und ein Mensch, der von Hand nachsieht, denselben
# Befehl benutzen.
#
#   bash tools/sync/build.sh <zielverzeichnis> [stufe] [programm ...]
set -uo pipefail
cd "$(dirname "$0")/../.."
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

rc=0
for p in $PROGS; do
    UPROF=""; UCRT="$OUT/crt.o"
    grep -qa '^profile app' "$USRC/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    if ! "$CC" $UPROF -c "$USRC/$p.fi" -o "$OUT/$p.o" > "$OUT/$p.err" 2>&1; then
        echo "FEHLER: firnc$STUFE uebersetzt $p.fi nicht"
        sed 's/^/    /' "$OUT/$p.err" | head -12
        rc=1
        continue
    fi
    if ! ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F$STUFE.u_start" \
        -o "$OUT/$p.elf" $UCRT "$OUT/$p.o" 2> "$OUT/$p.lderr"; then
        echo "FEHLER: ld scheitert an $p"
        sed 's/^/    /' "$OUT/$p.lderr" | head -8
        rc=1
        continue
    fi
    strip --strip-all "$OUT/$p.elf"
done
exit $rc
