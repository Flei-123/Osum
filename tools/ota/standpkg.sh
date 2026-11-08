#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
NAME=${1:?usage: standpkg.sh <package-dir-name> <stand-dir>}
STAND=${2:?usage: standpkg.sh <package-dir-name> <stand-dir>}
[ -d "pakete/$NAME" ] || { echo "== pakete/$NAME does not exist"; exit 1; }
[ -d "$STAND" ] || { echo "== $STAND is not a directory"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash pakete/bauen.sh "$T" > "$T/log" 2>&1
PKG=$(sed -n 's/^name=//p' "pakete/$NAME/rezept" | head -1)
OPKF=$(ls "$T/$PKG"-*.opk 2>/dev/null | head -1)
[ -n "$OPKF" ] || { echo "== $PKG package not built:"; grep -i "$PKG" "$T/log"; exit 1; }
FASSUNG=$(sed -n 's/^\(revision\|fassung\)=//p' "pakete/$NAME/INFO" 2>/dev/null | head -1)
[ -n "$FASSUNG" ] || FASSUNG=$(sed -n 's/^version=//p' "pakete/$NAME/rezept" | head -1)
cp "$OPKF" "$STAND/$PKG-${FASSUNG%%.*}.opk" && echo "ok: $STAND/$PKG-${FASSUNG%%.*}.opk"
