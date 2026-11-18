#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/pkgdev/lib.sh

usage() {
    echo "usage: bash tools/pkgdev/run.sh list"
    echo "       bash tools/pkgdev/run.sh <pkg> build"
    echo "       bash tools/pkgdev/run.sh <pkg> shots [pages=0,1,3] [mode=light|dark] [scale=1|2]"
    echo "       bash tools/pkgdev/run.sh <pkg> clean"
    exit 2
}

[ $# -ge 1 ] || usage
if [ "$1" = list ]; then
    for name in $(pkg_list); do echo "$name: $(pkg_get "$name" title) -> /bin/$(pkg_get "$name" prog)"; done
    exit 0
fi
NAME=$1
ACTION=${2:-shots}
shift 2 2> /dev/null || shift $#
pkg_manifest "$NAME" > /dev/null || exit 2
pkg_sources_ok "$NAME" || exit 1
PROG=$(pkg_get "$NAME" prog)
. tools/lib/firnenv.sh

pkg_build() {
    local out=$1 t0=$EPOCHREALTIME
    bash tools/sync/build.sh "$out" 0 "$PROG" || return 1
    stamp build "$t0"
}

pkg_shots() {
    local pages="" mode=light scale=1 arg
    for arg in "$@"; do
        case "$arg" in
            pages=*) pages=${arg#pages=} ;;
            mode=*) mode=${arg#mode=} ;;
            scale=*) scale=${arg#scale=} ;;
            *) echo "pkgdev: unknown option $arg" >&2; return 2 ;;
        esac
    done
    local t0=$EPOCHREALTIME tmp dest
    tmp=$(mktemp -d) || return 1
    trap 'rm -rf "$tmp"' RETURN
    dest="$PKGDEV_SHOTS/$NAME/$mode-${scale}x"
    mkdir -p "$PKGDEV_CACHE/$NAME"
    export DESIGNBUILD="$PKGDEV_CACHE/$NAME"
    local count=${PKGDEV_ALL_PAGES:-35} halt
    [ -n "$pages" ] && count=$(echo "$pages" | tr ',' '\n' | wc -l)
    halt=$((PKGDEV_BOOT_SECONDS + PKGDEV_PAGE_SECONDS * count))
    AUDIT_PAGES=$pages "$HEAVY" bash tools/settingsaudit/run.sh "$tmp/run" "mode=$mode" "uiscale=$scale" "halt=$halt" > "$tmp/audit.log" 2>&1
    [ -s "$tmp/run/serial.txt" ] || { tail -20 "$tmp/audit.log"; echo "pkgdev: no serial output, QEMU run failed" >&2; return 1; }
    stamp qemu "$t0"
    rm -rf "$dest"
    python3 -I tools/settingsaudit/ppm2png.py "$tmp/run" "$dest" 100 > /dev/null || return 1
    python3 -I tools/pkgdev/sheet.py "$dest" || return 1
    stamp total "$t0"
    echo "$dest"
}

case "$ACTION" in
    build)
        out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
        pkg_build "$out" ;;
    shots) pkg_shots "$@" ;;
    clean) rm -rf "$PKGDEV_CACHE/$NAME" ;;
    *) usage ;;
esac
