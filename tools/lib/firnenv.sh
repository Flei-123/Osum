#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
FIRN_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
FIRN_HOME=${FIRN_HOME:-$HOME/.firn}

firnenv_fail() {
    printf 'firnenv: %s\n' "$1" >&2
    exit 1
}

firnenv_version() {
    if [ -n "${FIRN_VERSION:-}" ]; then
        printf '%s\n' "$FIRN_VERSION"
        return 0
    fi
    local pin="$FIRN_ROOT/firn.toolchain" word version
    [ -f "$pin" ] || firnenv_fail "firn.toolchain is missing in $FIRN_ROOT"
    read -r word version < "$pin"
    [ "$word" = firn ] && [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        || firnenv_fail "firn.toolchain must contain 'firn X.Y.Z'"
    printf '%s\n' "$version"
}

firnenv_link_font_alias() {
    local target="$FIRN_TOOLCHAIN/lib/font/ttf.fi" link="$FIRN_ROOT/lib/font/fuittf.fi"
    [ -f "$target" ] || return 0
    [ "$(readlink "$link" 2>/dev/null)" = "$target" ] && return 0
    mkdir -p "$FIRN_ROOT/lib/font"
    ln -sfn "$target" "$link"
}

firnenv_need_firnc1() {
    [ -x "$FIRNC1" ] && return 0
    mkdir -p "$(dirname "$FIRNC1")"
    ln -sfn "$FIRN_TOOLCHAIN/lib" "$FIRN_CACHE/lib"
    local tmp
    tmp=$(mktemp "$FIRNC1.XXXXXX") || firnenv_fail "cannot create a temporary file for firnc1"
    if ! "$FIRNC" "$FIRN_TOOLCHAIN/src/firnc1.fi" -o "$tmp" > "$tmp.log" 2>&1; then
        tail -5 "$tmp.log" >&2
        rm -f "$tmp" "$tmp.log"
        firnenv_fail "building firnc1 failed"
    fi
    chmod +x "$tmp"
    rm -f "$tmp.log"
    mv -f "$tmp" "$FIRNC1"
}

FIRN_VERSION_USED=$(firnenv_version)
FIRN_TOOLCHAIN="$FIRN_HOME/versions/$FIRN_VERSION_USED"
[ -x "$FIRN_TOOLCHAIN/bin/firnc" ] && [ -d "$FIRN_TOOLCHAIN/lib" ] \
    || firnenv_fail "Firn $FIRN_VERSION_USED is not installed (run: firn install $FIRN_VERSION_USED)"

FIRNC=${FIRNC:-$FIRN_TOOLCHAIN/bin/firnc}
FIRN_STD="$FIRN_TOOLCHAIN/lib/std"
FIRN_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/osum-firn/$FIRN_VERSION_USED"
FIRNC1=${FIRNC1:-$FIRN_CACHE/bin/firnc1}
export FIRN_USE_AS="${FIRN_USE_AS-1}"
export FIRNLIB="$FIRN_ROOT/lib"
export FIRNC FIRNC1 FIRN_STD FIRN_TOOLCHAIN
firnenv_link_font_alias

firnenv_prepare_old_tree() {
    local tree=$1 legacy
    [ -f "$tree/tools/lib/firnenv.sh" ] && return 0
    legacy="$tree/vendor/firn"
    [ -x "$legacy/bin/firnc" ] && return 0
    firnenv_need_firnc1
    mkdir -p "$legacy/bin"
    printf '#!/bin/sh\nexport FIRN_USE_AS="${FIRN_USE_AS-1}"\nexec "%s" "$@"\n' "$FIRNC" > "$legacy/bin/firnc"
    chmod +x "$legacy/bin/firnc"
    ln -sfn "$FIRNC1" "$legacy/bin/firnc1"
    ln -sfn "$FIRN_TOOLCHAIN/lib" "$legacy/lib"
}
