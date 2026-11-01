#!/usr/bin/env bash
set -uo pipefail

NAME=${1:-}
if [[ -z $NAME ]]; then
    echo "Usage: tools/kfind.sh <module name without .fi>" >&2
    exit 1
fi

WURZEL=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

mapfile -t TREFFER < <(find "$WURZEL/kernel" \
    -path "$WURZEL/kernel/user" -prune -o \
    -path "$WURZEL/kernel/app" -prune -o \
    -name "$NAME.fi" -type f -print 2>/dev/null | sort)

case ${#TREFFER[@]} in
    1) echo "${TREFFER[0]}" ;;
    0) echo "kfind: '$NAME.fi' liegt nirgends unter kernel/" >&2; exit 1 ;;
    *) { echo "kfind: '$NAME.fi' liegt MEHRFACH unter kernel/:"
         printf '  %s\n' "${TREFFER[@]}"
         echo "  Two modules with the same name are a collision in Firn."
       } >&2; exit 1 ;;
esac
