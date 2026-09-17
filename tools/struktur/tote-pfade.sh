#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/struktur/tote-pfade.sh -- WELCHER LAEUFER ZEIGT INS LEERE?
#
# Nach dem Umzug nennt ein Testlaeufer vielleicht noch
# `kernel/kstate.fi`, obwohl die Datei jetzt `kernel/lib/kstate.fi`
# heisst. Das faellt NICHT beim Bauen auf -- es faellt auf, wenn ein
# `grep` nichts findet und der Laeufer eine falsche Zahl misst oder
# rot wird.
#
# Dieses Skript sucht in `tools/` und `test.sh` nach Pfaden der Form
# `kernel/<name>.fi`, die es NICHT MEHR GIBT, und meldet sie mit
# Datei und Zeile. Kommentare werden uebersprungen -- eine Prosazeile
# "siehe kernel/fs.fi" ist ungenau, aber sie bricht nichts.
#
#   bash tools/struktur/tote-pfade.sh          # Liste, Code 1 bei Fund
#   bash tools/struktur/tote-pfade.sh --alle   # auch Kommentare zeigen
set -uo pipefail
cd "$(dirname "$0")/../.."

ALLE=0
[[ ${1:-} == --alle ]] && ALLE=1

GEFUNDEN=0
KOMMENTARE=0

while IFS= read -r treffer; do
    datei=${treffer%%:*}
    rest=${treffer#*:}
    zeile=${rest%%:*}
    text=${rest#*:}
    # Der genannte Pfad
    pfad=$(echo "$text" | grep -oE 'kernel/[a-z0-9_]+\.fi' | head -1)
    [[ -z $pfad ]] && continue
    # Gibt es ihn?
    [[ -e $pfad ]] && continue
    # Liegt die Datei woanders?
    name=$(basename "$pfad" .fi)
    neu=$(find kernel -path kernel/user -prune -o -path kernel/app -prune -o \
          -name "$name.fi" -type f -print 2>/dev/null | head -1)
    nackt=$(echo "$text" | sed 's/^[[:space:]]*//')
    if [[ $nackt == \#* || $nackt == //* ]]; then
        KOMMENTARE=$((KOMMENTARE + 1))
        [[ $ALLE == 1 ]] && echo "  (Kommentar) $datei:$zeile  $pfad -> ${neu:-NIRGENDS}"
        continue
    fi
    echo "TOT  $datei:$zeile"
    echo "     nennt $pfad, liegt aber ${neu:-nirgends mehr}"
    GEFUNDEN=$((GEFUNDEN + 1))
# Nur Dateien, die AUSGEFUEHRT werden. `.tsv`, `.md`, `.c`, `.s` und
# die eigenen Werkzeuge bleiben aussen vor: die TSV-Tafeln unter
# `tools/english/` sind das PROTOKOLL einer frueheren Runde und
# nennen die Pfade von damals mit Absicht.
done < <(grep -rnE 'kernel/[a-z0-9_]+\.fi' tools/ test.sh 2>/dev/null |
         grep -E '^(test\.sh|tools/[^:]*\.(sh|py))' |
         grep -vE '^tools/struktur/')

echo
echo "tote Pfade in ausfuehrbarem Code: $GEFUNDEN"
echo "in Kommentaren (unkritisch):      $KOMMENTARE"
[[ $GEFUNDEN -gt 0 ]] && exit 1
exit 0
