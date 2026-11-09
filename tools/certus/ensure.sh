#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
CERTUS_REPO=${CERTUS_REPO:-/root/certus-ui}
CERTUS_FIRNC=${CERTUS_FIRNC:-$ROOT/vendor/firn/bin/firnc}
CACHE=${CERTUS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/osum/certus}

[ -d "$CERTUS_REPO/lib/browser" ] && [ -x "$CERTUS_FIRNC" ] || exit 0
head=$(git -C "$CERTUS_REPO" rev-parse HEAD 2>/dev/null || echo nogit)
dirty=$(git -C "$CERTUS_REPO" status --porcelain --untracked-files=no 2>/dev/null | sha256sum | cut -c1-16)
inputs=$( (cat kernel/user/ulib.fi kernel/user/fuiapp/wlib.fi kernel/user/wlibc.fi lib/icons.fi lib/utf8.fi \
    kernel/user/certus/build.sh kernel/user/certus/entkern.py kernel/user/certus/splitstems.py kernel/user/certus/inlineconsts.py kernel/user/certus/lowerintrinsics.py kernel/user/certus/merge-stems.txt kernel/user/certus/shims/deflate_limited.fi kernel/user/sysstub.s kernel/user/user.ld
    find lib/libc kernel/user/fuiapp kernel/user/wlibc kernel/user/uitheme -type f | sort | xargs cat
    sha256sum "$CERTUS_FIRNC") | sha256sum | cut -c1-16)
key="$head-$dirty-$inputs"
elf="$CACHE/$key.elf"
if [ ! -s "$elf" ]; then
    mkdir -p "$CACHE"
    tmp=$(mktemp "$CACHE/build.XXXXXX")
    if bash kernel/user/certus/build.sh "$tmp" > "$CACHE/$key.log" 2>&1 && [ -s "$tmp" ]; then
        mv "$tmp" "$elf"
    else
        rm -f "$tmp"
        tail -5 "$CACHE/$key.log" >&2
        exit 0
    fi
fi
printf '%s\n' "$elf"
