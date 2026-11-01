#!/usr/bin/env bash
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

    for SUFFIX in -aus -off; do
        GEGEN=$(find kernel -path kernel/user -prune -o -path kernel/app -prune -o \
            -name "$MODUL$SUFFIX.fi" -type f -print | head -1)
        if [[ -n $GEGEN ]]; then
            git mv "$GEGEN" "kernel/$ZIEL/$MODUL$SUFFIX.fi" || exit 1
            echo "  (Gegenfassung $MODUL$SUFFIX.fi zieht mit)"
        fi
    done

    NEU="${ZIEL//\//.}.$MODUL"

    ALT_DIR=$(dirname "${QUELLE#kernel/}")
    if [[ $ALT_DIR == "." ]]; then
        MUSTER="$MODUL"
    else
        MUSTER="(${ALT_DIR//\//.}\.)?$MODUL"
    fi
    N=0
    while IFS= read -r f; do
        sed -i -E "s|^([ \t]*)import[ \t]+$MUSTER([ \t]*)(//.*)?$|\1import $NEU\2\3|" "$f"
        N=$((N + 1))
    done < <(find kernel -path kernel/user -prune -o -path kernel/app -prune -o \
             -name '*.fi' -type f -print |
             xargs -r grep -laE "^[ \t]*import[ \t]+$MUSTER[ \t]*(//.*)?$" 2>/dev/null)
    echo "  $MODUL -> $ZIEL/  ($N import-Zeilen)"
    GESAMT=$((GESAMT + N))
done

echo "zusammen $GESAMT import-Zeilen angepasst"
