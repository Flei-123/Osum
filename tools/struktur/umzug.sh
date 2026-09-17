#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/struktur/umzug.sh -- EINE GRUPPE Dateien in ihre Schicht ziehen.
#
#   bash tools/struktur/umzug.sh <verzeichnis> <modul> [<modul> ...]
#   z. B. bash tools/struktur/umzug.sh acpi acpi aml amlev amlns amlobj
#
# Was es tut:
#   1. `git mv` jeder genannten Datei in `kernel/<verzeichnis>/`.
#   2. In JEDER .fi unter kernel/ die import-Zeile auf den neuen Pfad
#      setzen -- egal, ob sie vorher flach oder in einem Ordner stand.
#
# WARUM DAS REICHT: Firn spricht ein Modul unter dem LETZTEN Teil des
# Pfades an (`/root/firn/compiler/src/modules.rs`, `imp.path.last()`).
# Nach `import acpi.aml` heisst das Modul weiterhin `aml`, und jede
# Aufrufstelle `aml.methode(...)` bleibt Zeichen fuer Zeichen stehen.
#
# WICHTIG ZUR SUCHORDNUNG: der Uebersetzer sucht zuerst NEBEN DER
# IMPORTIERENDEN DATEI, dann neben der Wurzel (`kmain.fi`). Weil alle
# Schichtverzeichnisse unter `kernel/` liegen und `kmain.fi` oben
# steht, ist der Pfad ab `kernel/` fuer JEDEN Aufrufer richtig --
# auch fuer einen, der selbst in einem Unterordner liegt. Ein
# Aufrufer in `kernel/drv/snd/` schreibt also ebenfalls
# `import acpi.aml`, nicht `../../acpi/aml`.
#
# Die Gegenfassungen (`wg-aus.fi`, `ext4-aus.fi`, ...) ziehen MIT --
# sie muessen an derselben Stelle liegen wie die Datei, die sie
# ersetzen, sonst findet `tools/build-kernel.sh` sie zwar (es sucht),
# aber der Baum waere unordentlich.
set -uo pipefail
cd "$(dirname "$0")/../.."

ZIEL=${1:-}
shift || true
if [[ -z $ZIEL || $# -eq 0 ]]; then
    sed -n '3,6p' "$0"
    exit 1
fi

mkdir -p "kernel/$ZIEL"
GESAMT=0

for MODUL in "$@"; do
    # Wo liegt die Datei gerade?
    QUELLE=$(find kernel -path kernel/user -prune -o -path kernel/app -prune -o \
        -name "$MODUL.fi" -type f -print | head -1)
    if [[ -z $QUELLE ]]; then
        echo "umzug: $MODUL.fi liegt nirgends unter kernel/" >&2
        exit 1
    fi
    ZIELPFAD="kernel/$ZIEL/$MODUL.fi"
    if [[ $QUELLE == "$ZIELPFAD" ]]; then
        echo "  $MODUL liegt schon in $ZIEL/"
        continue
    fi
    git mv "$QUELLE" "$ZIELPFAD" || exit 1

    # Die Gegenfassung, falls es eine gibt, zieht mit.
    for SUFFIX in -aus -off; do
        GEGEN=$(find kernel -path kernel/user -prune -o -path kernel/app -prune -o \
            -name "$MODUL$SUFFIX.fi" -type f -print | head -1)
        if [[ -n $GEGEN ]]; then
            git mv "$GEGEN" "kernel/$ZIEL/$MODUL$SUFFIX.fi" || exit 1
            echo "  (Gegenfassung $MODUL$SUFFIX.fi zieht mit)"
        fi
    done

    # Der neue Importpfad: Verzeichnis mit Punkten statt Schraegstrichen.
    NEU="${ZIEL//\//.}.$MODUL"
    N=0
    while IFS= read -r f; do
        # Trifft `import <modul>` UND `import <alterpfad>.<modul>`,
        # jeweils nur als ganze Zeile.
        sed -i -E "s|^([ \t]*)import[ \t]+([A-Za-z_][A-Za-z0-9_.]*\.)?$MODUL([ \t]*)(//.*)?$|\1import $NEU\3\4|" "$f"
        N=$((N + 1))
    done < <(grep -rlaE "^[ \t]*import[ \t]+([A-Za-z_][A-Za-z0-9_.]*\.)?$MODUL[ \t]*(//.*)?$" \
             --include='*.fi' kernel/ 2>/dev/null)
    echo "  $MODUL -> $ZIEL/  ($N import-Zeilen)"
    GESAMT=$((GESAMT + N))
done

echo "zusammen $GESAMT import-Zeilen angepasst"
