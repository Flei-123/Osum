#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/pkgdev/lib.sh

usage() {
    echo "usage: bash tools/pkgdev/ship.sh <pkg> [--gates] [--publish] [\"notes\"]"
    echo "  default: build check + dry feed publish of origin/main (nothing goes live)"
    echo "  --gates    run the gates listed in the package manifest first (heavy)"
    echo "  --publish  publish for real (HP dev feed system/dev); needs HEAD merged into origin/main"
    exit 2
}

[ $# -ge 1 ] || usage
NAME=$1; shift
pkg_manifest "$NAME" > /dev/null || exit 2
GATES=0; PUBLISH=0; NOTES=""
for arg in "$@"; do
    case "$arg" in
        --gates) GATES=1 ;;
        --publish) PUBLISH=1 ;;
        *) NOTES=$arg ;;
    esac
done
fail() { echo "ship: $*" >&2; exit 1; }

git diff --quiet HEAD -- . || fail "working tree not clean, commit first"
bash tools/pkgdev/run.sh "$NAME" build || fail "build failed"

if [ "$GATES" = 1 ]; then
    for gate in $(pkg_get "$NAME" gates); do
        echo "ship: gate $gate"
        "$HEAVY" bash "tools/$gate/run.sh" > "/dev/null" 2>&1 || fail "gate $gate red"
    done
fi

git fetch -q origin
if [ "$PUBLISH" = 1 ]; then
    git merge-base --is-ancestor HEAD origin/main || fail "HEAD is not in origin/main, merge and push first"
    exec bash tools/ota/publish-dev.sh "${NOTES:-$(pkg_get "$NAME" title) update}"
fi
exec bash tools/ota/publish-dev.sh --dry "${NOTES:-$(pkg_get "$NAME" title) update}"
