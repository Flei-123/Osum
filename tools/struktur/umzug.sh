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

    # WELCHE PRAEFIXE DUERFEN ERSETZT WERDEN? NUR die, die auf eine
    # Datei IM KERNBAUM zeigen -- also der nackte Name und der Ordner,
    # in dem die Datei zuletzt lag.
    #
    # WARUM DIESE EINSCHRAENKUNG: ein Muster wie `(irgendwas\.)?$MODUL`
    # trifft auch `libc.errno`, `libc.mem` und `libc.proc` -- Module aus
    # `lib/libc/`, die `kernel/user/` benutzt und die mit dem Kern
    # nichts zu tun haben. Ein erster Lauf hat genau das getan: 40
    # Zeilen in 33 Programmen umgebogen (`libc.errno` -> `lib.errno`),
    # und `kernel/user/ls.fi` liess sich nicht mehr uebersetzen.
    ALT_DIR=$(dirname "${QUELLE#kernel/}")
    if [[ $ALT_DIR == "." ]]; then
        MUSTER="$MODUL"
    else
        MUSTER="(${ALT_DIR//\//.}\.)?$MODUL"
    fi
    N=0
    while IFS= read -r f; do
        # Trifft `import <modul>` UND `import <alterpfad>.<modul>`,
        # jeweils nur als ganze Zeile.
        sed -i -E "s|^([ \t]*)import[ \t]+$MUSTER([ \t]*)(//.*)?$|\1import $NEU\2\3|" "$f"
        N=$((N + 1))
        # NUR der Kernbaum. `kernel/user/` und `kernel/app/` sind
        # eigene Programme mit eigenen Wurzeln -- und sie haben Module
        # GLEICHEN NAMENS: `kernel/user/nidx.fi` neben `kernel/fs/nidx.fi`,
        # dazu crash, hwid, netmon, netview, power, wmplug. Ein `import
        # nidx` dort meint die Datei NEBENAN (Suchordnung Schritt 1) und
        # darf nicht auf den Kern umgebogen werden. Ein erster Lauf hat
        # genau das getan und K17 auf 18/31 gedrueckt.
    done < <(find kernel -path kernel/user -prune -o -path kernel/app -prune -o \
             -name '*.fi' -type f -print |
             xargs -r grep -laE "^[ \t]*import[ \t]+$MUSTER[ \t]*(//.*)?$" 2>/dev/null)
    echo "  $MODUL -> $ZIEL/  ($N import-Zeilen)"
    GESAMT=$((GESAMT + N))
done

echo "zusammen $GESAMT import-Zeilen angepasst"
