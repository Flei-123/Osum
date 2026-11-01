#!/usr/bin/env bash
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
    pfad=$(echo "$text" | grep -oE 'kernel/[a-z0-9_]+\.fi' | head -1)
    [[ -z $pfad ]] && continue
    [[ -e $pfad ]] && continue
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
    echo "     names $pfad, but it is ${neu:-nowhere anymore}"
    GEFUNDEN=$((GEFUNDEN + 1))
done < <(grep -rnE 'kernel/[a-z0-9_]+\.fi' tools/ test.sh 2>/dev/null |
         grep -E '^(test\.sh|tools/[^:]*\.(sh|py))' |
         grep -vE '^tools/struktur/')

echo
echo "tote Pfade in ausfuehrbarem Code: $GEFUNDEN"
echo "in Kommentaren (unkritisch):      $KOMMENTARE"
[[ $GEFUNDEN -gt 0 ]] && exit 1
exit 0
