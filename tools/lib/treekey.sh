# SPDX-License-Identifier: GPL-2.0-only
. "$(dirname "${BASH_SOURCE[0]}")/../kernel/buildcache.sh"

osum_tree_key() {
    local root=${1:-.}
    {
        (cd "$root" && bc_tree_hash kernel lib vendor/firn/lib tools/build-kernel.sh)
        cat "$root/vendor/firn/.gebaut" 2>/dev/null
    } | sha256sum | cut -c1-12
}

osum_keyed_builddir() {
    local base=$1 root=${2:-.} dir
    dir=$base/$(osum_tree_key "$root")
    mkdir -p "$dir" || return 1
    find "$base" -mindepth 1 -maxdepth 1 -type d -mtime +2 ! -path "$dir" -exec rm -rf {} + 2>/dev/null
    touch "$dir"
    printf '%s' "$dir"
}
