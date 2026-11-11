#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
entry=$1
. "$root/tools/lib/firnenv.sh"
declare -A seen
walk() {
    local file=$1 dir mod rel found cand
    dir=$(dirname "$file")
    [[ -n ${seen[$file]:-} ]] && return
    seen[$file]=1
    printf '%s\n' "$file"
    while read -r mod; do
        rel=${mod//./\/}.fi
        found=""
        for cand in "$dir/$rel" "$root/lib/$rel" "$FIRN_TOOLCHAIN/lib/$rel"; do
            if [[ -f $cand ]]; then found=$cand; break; fi
        done
        [[ -n $found ]] || { echo "closure: unresolved import $mod in $file" >&2; exit 1; }
        walk "$found"
    done < <(sed -n 's/^import[[:space:]]\+\([A-Za-z0-9_.]\+\).*/\1/p' "$file")
}
walk "$(cd "$(dirname "$entry")" && pwd)/$(basename "$entry")"
