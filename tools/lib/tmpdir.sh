osum_tmp_guard() {
    local given=$1 dir=$2
    [ -z "$given" ] || return 0
    [ -n "$dir" ] && [ -d "$dir" ] || return 0
    [ -z "${OSUM_KEEP_TMP:-}" ] || return 0
    OSUM_TMP_OWNED="${OSUM_TMP_OWNED:-} $dir"
    trap 'for d in $OSUM_TMP_OWNED; do rm -rf "$d"; done' EXIT
}
