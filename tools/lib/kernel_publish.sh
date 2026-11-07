# SPDX-License-Identifier: GPL-2.0-only
kernel_publish() {
    local spec=$1 kernel=$2 gz=${3:-${KERNEL_GZ:-0}}
    mcopy -i "$spec" -o "$kernel" ::/osum.mb || return 1
    mdel -i "$spec" ::/osum.mb.gz 2>/dev/null
    [ "$gz" = 1 ] || return 0
    local tmp rc
    tmp=$(mktemp)
    gzip -9 -n -c "$kernel" > "$tmp" && mcopy -i "$spec" -o "$tmp" ::/osum.mb.gz
    rc=$?
    rm -f "$tmp"
    return $rc
}
