#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."

MODUL=${1:-}
ORDNER=${2:-}
if [[ -z $MODUL || -z $ORDNER ]]; then
    sed -n '3,8p' "$0"
    exit 1
fi

QUELLE="kernel/$MODUL.fi"
ZIEL="kernel/$ORDNER/$MODUL.fi"

[[ -f $QUELLE ]] || { echo "es gibt kein $QUELLE" >&2; exit 1; }
[[ -e $ZIEL ]] && { echo "$ZIEL steht schon da" >&2; exit 1; }

mkdir -p "kernel/$ORDNER"
git mv "$QUELLE" "$ZIEL" || exit 1

N=0
while IFS= read -r f; do
    sed -i -E "s|^([ \t]*)import[ \t]+$MODUL[ \t]*\$|\1import $ORDNER.$MODUL|" "$f"
    N=$((N + 1))
done < <(grep -rlE "^[ \t]*import[ \t]+$MODUL[ \t]*\$" --include='*.fi' kernel/ 2>/dev/null)

echo "$MODUL -> $ORDNER/  ($N import-Zeilen angepasst)"
