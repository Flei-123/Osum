#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=${1:?output file}
modules=(lib identity cpu gpu input net firefox klog main)
{
    echo '#!/bin/busybox sh'
    for name in "$here"/hp/awk/*.awk; do
        base=$(basename "$name" .awk)
        echo "emit_awk_$base() {"
        echo "    /bin/busybox cat <<'AWK_EOF'"
        cat "$name"
        echo "AWK_EOF"
        echo "}"
    done
    for m in "${modules[@]}"; do
        cat "$here/hp/$m.sh"
    done
    cat <<'MAIN'
[ -f "$HPD_ROOT/config.sh" ] && . "$HPD_ROOT/config.sh"
case "${1:-}" in
    launch) launch ;;
    run) install_awk; run_all ;;
    *) echo "usage: hpdaily.sh launch|run" >&2; exit 2 ;;
esac
MAIN
} > "$out"
