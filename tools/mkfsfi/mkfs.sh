#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CACHE="${MKFS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/osum/mkfs}"
mkdir -p "$CACHE"

. "$ROOT/tools/lib/firnenv.sh"

tree_hash() {
    (cd "$ROOT" && { sha256sum "$FIRNC" tools/k11/hostcrt.s tools/k11/hostbuild.sh kernel/user/mkfs.fi kernel/user/user.ld
        find lib kernel/user/mkfs -type f -print0 | sort -z | xargs -0 cat | sha256sum; } | sha256sum | cut -c1-24)
}

KEY="$(tree_hash)"
BIN="$CACHE/mkfs-$KEY"
if [ ! -x "$BIN" ]; then
    exec 9>"$CACHE/lock"
    flock 9
    if [ ! -x "$BIN" ]; then
        WORK="$(mktemp -d "$CACHE/build.XXXXXX")"
        if ! (cd "$ROOT" && HOSTOUT="$WORK" bash tools/k11/hostbuild.sh mkfs) >"$WORK/log" 2>&1; then
            echo "mkfs: host build failed" >&2
            cat "$WORK/log" >&2
            rm -rf "$WORK"
            exit 1
        fi
        mv "$WORK/mkfs" "$BIN.tmp" && mv "$BIN.tmp" "$BIN"
        rm -rf "$WORK"
        ls -t "$CACHE"/mkfs-* 2>/dev/null | tail -n +9 | xargs -r rm -f
    fi
    flock -u 9
fi

if [ "${1:-}" = "build" ] && [ $# -ge 3 ]; then
    BKEY="$({ cd "$ROOT" && cat tools/marke/*.py tools/marke/legacy-slugs.txt tools/mkfsfi/brandmap.py marke.conf; env | grep '^OSUM_MARKE_' | sort; } | sha256sum | cut -c1-24)"
    MAP="$CACHE/brand-$BKEY.map"
    if [ ! -s "$MAP" ]; then
        python3 "$ROOT/tools/mkfsfi/brandmap.py" "$MAP.$$" || exit 1
        mv "$MAP.$$" "$MAP"
        ls -t "$CACHE"/brand-*.map 2>/dev/null | tail -n +5 | xargs -r rm -f
    fi
    exec "$BIN" "$1" "$2" "$3" "--brand=$MAP" "${@:4}"
fi
exec "$BIN" "$@"
